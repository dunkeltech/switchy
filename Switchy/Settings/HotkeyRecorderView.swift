//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import SwiftUI

/// SwiftUI wrapper around a button that "records" a key combination.
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.combo = combo
        button.onCapture = { newCombo in
            combo = newCombo
        }
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        if !nsView.isRecording {
            nsView.combo = combo
        }
    }
}

/// SwiftUI wrapper for recording a single key (including pure modifiers like ⇧),
/// e.g. for the reverse key.
struct SingleKeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt16

    func makeNSView(context: Context) -> SingleKeyRecorderButton {
        let button = SingleKeyRecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.keyCode = keyCode
        button.onCapture = { code in keyCode = code }
        return button
    }

    func updateNSView(_ nsView: SingleKeyRecorderButton, context: Context) {
        if !nsView.isRecording {
            nsView.keyCode = keyCode
        }
    }
}

/// Button that records a single key. Runs primarily via the global HID event tap (so
/// it also captures pure modifiers like the left ⇧ key).
final class SingleKeyRecorderButton: NSButton {
    var onCapture: ((UInt16) -> Void)?

    var keyCode: UInt16 = 56 {
        didSet { updateTitle() }
    }

    private(set) var isRecording = false {
        didSet { updateTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        if let tap = EventTapController.shared, tap.isRunning {
            tap.beginCaptureSingleKey { [weak self] code in
                self?.finish(with: code)
            }
        } else {
            window?.makeFirstResponder(self) // Fallback: non-modifier keys only
        }
    }

    private func stopRecording() {
        EventTapController.shared?.cancelCaptureSingleKey()
        isRecording = false
    }

    private func finish(with code: UInt16) {
        keyCode = code
        isRecording = false
        onCapture?(code)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { stopRecording(); return } // Esc cancels
        finish(with: event.keyCode)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { isRecording = false }
        return super.resignFirstResponder()
    }

    private func updateTitle() {
        title = isRecording ? String(localized: "Press keys…") : KeyCombo.keyName(for: keyCode)
    }
}

/// Button that enters recording mode on click and captures the next key combination
/// (modifier + key).
///
/// Recording runs primarily via the global HID event tap (`EventTapController`) so
/// that system-reserved combinations like ⌘-Tab are captured too. If the tap is
/// unavailable (e.g. missing permission), a `keyDown` fallback is used.
final class RecorderButton: NSButton {
    var onCapture: ((KeyCombo) -> Void)?

    var combo: KeyCombo? {
        didSet { updateTitle() }
    }

    private(set) var isRecording = false {
        didSet { updateTitle() }
    }

    /// Whether the current recording runs via the global tap.
    private var usingTap = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = String(localized: "Not set")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        if let tap = EventTapController.shared, tap.isRunning {
            usingTap = true
            tap.beginCapture { [weak self] captured in
                self?.finish(with: captured)
            }
        } else {
            // Fallback without the tap: via the responder chain (does not capture
            // system-reserved combinations).
            usingTap = false
            window?.makeFirstResponder(self)
        }
    }

    private func stopRecording() {
        if usingTap {
            EventTapController.shared?.cancelCapture()
        }
        usingTap = false
        isRecording = false
    }

    private func finish(with captured: KeyCombo) {
        combo = captured
        usingTap = false
        isRecording = false
        onCapture?(captured)
    }

    // MARK: - Fallback without the tap

    override func keyDown(with event: NSEvent) {
        guard isRecording, !usingTap else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // Esc cancels
            stopRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection(KeyCombo.relevantFlags)
        guard !modifiers.intersection([.command, .option, .control]).isEmpty else {
            NSSound.beep()
            return
        }
        finish(with: KeyCombo(keyCode: event.keyCode, modifiers: modifiers))
    }

    override func resignFirstResponder() -> Bool {
        if isRecording, !usingTap {
            isRecording = false
        }
        return super.resignFirstResponder()
    }

    private func updateTitle() {
        if isRecording {
            title = String(localized: "Press keys…")
        } else {
            title = combo?.displayString ?? String(localized: "Not set")
        }
    }
}
