//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import CoreGraphics

/// The mode in which the overlay is opened.
enum SwitchMode {
    /// All windows of all apps.
    case global
    /// Only windows of the currently active app.
    case appFilter
}

/// Receives the hotkey gestures recognized by the event tap.
///
/// All methods are called on the main thread.
@MainActor
protocol HotkeyResponder: AnyObject {
    /// Whether the overlay is currently visible (determines whether key presses are swallowed).
    var isOverlayActive: Bool { get }

    /// Modifier is held and the navigation key is pressed for the first time → open overlay.
    func hotkeyActivate(mode: SwitchMode, reverse: Bool)
    /// Further navigation while the modifier is held.
    func hotkeyStep(reverse: Bool)
    /// Modifier released → confirm the selection.
    func hotkeyConfirm()
    /// `Esc` → cancel without switching.
    func hotkeyCancel()
}

/// Intercepts the configured hotkey combinations system-wide via a CoreGraphics event
/// tap – necessary because some of them sit deep in the system and a normal
/// `NSEvent` monitor is not enough.
final class EventTapController {
    private weak var responder: HotkeyResponder?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let keyEscape: Int64 = 53

    /// Modifiers whose release confirms the current overlay session (the triggering
    /// hotkey's modifiers, without Shift). Only touched on the main thread.
    private var activeTriggerMask: CGEventFlags = []

    /// Access for the hotkey recorder so it can record via the same (HID) tap – needed
    /// to capture system-reserved combinations like ⌘-Tab at all.
    static weak var shared: EventTapController?

    /// When set, the tap is in recording mode: the next key combination (with a
    /// modifier) is captured instead of processed normally.
    @MainActor private var captureHandler: ((KeyCombo) -> Void)?

    /// Recording mode for a single key (including pure modifiers like ⇧) – for the
    /// reverse key.
    @MainActor private var captureSingleKeyHandler: ((UInt16) -> Void)?

    /// State for the dedicated reverse key when it is a modifier (e.g. left ⇧):
    /// "armed" while it is held; a pure tap (release without an intervening key press)
    /// triggers a step back.
    private var reverseModifierArmed = false
    private var navPressedSinceReverseArm = false

    init(handler: HotkeyResponder) {
        self.responder = handler
        EventTapController.shared = self
    }

    // MARK: - Hotkey recording (for the settings recorder)

    /// Begins recording; `handler` is called once with the captured combination.
    @MainActor
    func beginCapture(_ handler: @escaping (KeyCombo) -> Void) {
        captureHandler = handler
    }

    /// Cancels an in-progress recording.
    @MainActor
    func cancelCapture() {
        captureHandler = nil
    }

    /// Begins recording a single key (including pure modifiers).
    @MainActor
    func beginCaptureSingleKey(_ handler: @escaping (UInt16) -> Void) {
        captureSingleKeyHandler = handler
    }

    /// Cancels the single-key recording.
    @MainActor
    func cancelCaptureSingleKey() {
        captureSingleKeyHandler = nil
    }

    /// Whether the tap is running (the recorder can then record via it).
    var isRunning: Bool { eventTap != nil }

    /// Starts the event tap. Requires the Accessibility permission.
    func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // HID level (instead of session level): only here do we sit *before* the
        // WindowServer's symbolic-hotkey processing and can actually intercept
        // system-wide combinations like ⌘-Tab (the Dock app switcher). A
        // `.cgSessionEventTap` never even sees ⌘-Tab.
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            NSLog("Switchy: failed to create event tap (missing Accessibility?)")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Re-enables the tap if the system disabled it (timeout/user input).
    fileprivate func reenable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Core logic – returns `true` when the event should be swallowed. Runs in the
    /// main run loop, hence `assumeIsolated`.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        MainActor.assumeIsolated {
            handleOnMain(type: type, event: event)
        }
    }

    @MainActor
    private func handleOnMain(type: CGEventType, event: CGEvent) -> Bool {
        guard let responder else { return false }
        let flags = event.flags
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let settings = AppSettings.shared

        // Recorder: single key (including pure modifiers like ⇧) – for the reverse key.
        if let handler = captureSingleKeyHandler {
            switch type {
            case .keyDown:
                if keycode == keyEscape { captureSingleKeyHandler = nil; return true }
                captureSingleKeyHandler = nil
                handler(UInt16(keycode))
                return true
            case .flagsChanged:
                // Capture a modifier at the moment it is pressed (bit set).
                if let bit = Self.deviceFlagBit(forModifierKeycode: UInt16(keycode)),
                   (flags.rawValue & bit) != 0 {
                    captureSingleKeyHandler = nil
                    handler(UInt16(keycode))
                }
                return false
            default:
                return false
            }
        }

        // Recorder: hotkey combination (keyDown only, with a modifier).
        if type == .keyDown, let handler = captureHandler {
            if keycode == keyEscape { captureHandler = nil; return true }
            let modifiers = Self.modifierFlags(from: flags)
            guard !modifiers.intersection([.command, .option, .control]).isEmpty else {
                return true // without a modifier: ignore, but swallow
            }
            captureHandler = nil
            handler(KeyCombo(keyCode: UInt16(keycode), modifiers: modifiers))
            return true
        }

        switch type {
        case .keyDown:
            // Any key press while the reverse modifier key is held counts as "not just
            // a tap" (prevents a double step for e.g. ⇧+Tab).
            if reverseModifierArmed { navPressedSinceReverseArm = true }

            if responder.isOverlayActive {
                // Dedicated reverse key as a normal (non-modifier) key.
                if !Self.isModifierKeycode(UInt16(keycode)),
                   keycode == Int64(settings.reverseKeyCode) {
                    responder.hotkeyStep(reverse: true)
                    return true
                }
                // Navigation key: Tab = forward, classic ⇧+Tab = backward.
                if let reverse = Self.match(flags: flags, keycode: keycode, combo: settings.globalHotkey)
                    ?? Self.match(flags: flags, keycode: keycode, combo: settings.appFilterHotkey) {
                    responder.hotkeyStep(reverse: reverse)
                    return true
                }
                if keycode == keyEscape {
                    responder.hotkeyCancel()
                    return true
                }
                return false
            }

            // Overlay closed: check whether a hotkey was triggered.
            if let reverse = Self.match(flags: flags, keycode: keycode, combo: settings.globalHotkey) {
                activeTriggerMask = triggerMask(for: settings.globalHotkey)
                responder.hotkeyActivate(mode: .global, reverse: reverse)
                return true
            }
            if let reverse = Self.match(flags: flags, keycode: keycode, combo: settings.appFilterHotkey) {
                activeTriggerMask = triggerMask(for: settings.appFilterHotkey)
                responder.hotkeyActivate(mode: .appFilter, reverse: reverse)
                return true
            }

        case .flagsChanged:
            handleReverseModifier(keycode: keycode, flags: flags, settings: settings)

            // Trigger modifier(s) released while the overlay is active → confirm.
            if responder.isOverlayActive,
               !activeTriggerMask.isEmpty,
               flags.intersection(activeTriggerMask).isEmpty {
                responder.hotkeyConfirm()
            }

        default:
            break
        }

        return false
    }

    /// Handles the dedicated reverse key when it is a modifier (e.g. left ⇧): a pure
    /// tap (press + release without an intervening key press) steps the selection back.
    @MainActor
    private func handleReverseModifier(keycode: Int64, flags: CGEventFlags, settings: AppSettings) {
        guard keycode == Int64(settings.reverseKeyCode),
              let bit = Self.deviceFlagBit(forModifierKeycode: UInt16(keycode)) else { return }

        let isDown = (flags.rawValue & bit) != 0
        if isDown {
            reverseModifierArmed = true
            navPressedSinceReverseArm = false
        } else {
            if reverseModifierArmed,
               !navPressedSinceReverseArm,
               let responder, responder.isOverlayActive {
                responder.hotkeyStep(reverse: true)
            }
            reverseModifierArmed = false
        }
    }

    /// Modifiers whose release confirms (hotkey modifiers without Shift).
    private func triggerMask(for combo: KeyCombo) -> CGEventFlags {
        combo.cgFlags.subtracting(.maskShift)
    }

    /// Device-specific flag bit for a (left/right) modifier key based on its keycode –
    /// lets us detect the exact press/release state of that key in a `flagsChanged`
    /// event. `nil` for non-modifier keys.
    private static func deviceFlagBit(forModifierKeycode keycode: UInt16) -> UInt64? {
        switch keycode {
        case 59: return 0x0000_0001 // ⌃ left
        case 56: return 0x0000_0002 // ⇧ left
        case 60: return 0x0000_0004 // ⇧ right
        case 55: return 0x0000_0008 // ⌘ left
        case 54: return 0x0000_0010 // ⌘ right
        case 58: return 0x0000_0020 // ⌥ left
        case 61: return 0x0000_0040 // ⌥ right
        case 62: return 0x0000_2000 // ⌃ right
        default: return nil
        }
    }

    private static func isModifierKeycode(_ keycode: UInt16) -> Bool {
        deviceFlagBit(forModifierKeycode: keycode) != nil
    }

    /// Converts CoreGraphics flags into `NSEvent.ModifierFlags` (for `KeyCombo`).
    private static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    /// Checks whether `flags`+`keycode` match the hotkey. Returns: `nil` = no match,
    /// otherwise `reverse` (true if Shift is additionally held).
    private static func match(
        flags: CGEventFlags,
        keycode: Int64,
        combo: KeyCombo
    ) -> Bool? {
        guard Int64(combo.keyCode) == keycode else { return nil }

        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let pressed = flags.intersection(relevant)
        let base = combo.cgFlags.intersection(relevant)

        if pressed == base {
            return false
        }
        // Reverse variant: same modifiers + Shift (only if the hotkey itself does not
        // contain Shift).
        if !base.contains(.maskShift), pressed == base.union(.maskShift) {
            return true
        }
        return nil
    }
}

/// C-compatible callback. Forwards to the instance via `refcon`.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.reenable()
        return Unmanaged.passUnretained(event)
    }

    let swallow = controller.handle(type: type, event: event)
    return swallow ? nil : Unmanaged.passUnretained(event)
}
