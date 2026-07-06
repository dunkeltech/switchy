//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import CoreGraphics

/// A key combination (modifiers + key), persistable and displayable.
struct KeyCombo: Codable, Equatable, Sendable {
    /// Virtual keycode (Carbon/`NSEvent.keyCode`).
    var keyCode: UInt16
    /// Raw value of the device-independent modifier flags (`NSEvent.ModifierFlags`).
    var modifierRawValue: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierRawValue = modifiers.intersection(Self.relevantFlags).rawValue
    }

    static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue).intersection(Self.relevantFlags)
    }

    /// Corresponding CoreGraphics flags (for event-tap matching).
    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    /// Human-readable representation, e.g. "⌥⇥" or "⌘⇧5".
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    /// Name mapping for common keycodes.
    static func keyName(for keyCode: UInt16) -> String {
        if let modifier = modifierKeys[keyCode] { return modifier }
        if let special = specialKeys[keyCode] { return special }
        if let char = printableKeys[keyCode] { return char }
        return "Key \(keyCode)"
    }

    /// Pure modifier keys (left/right) – used e.g. for the reverse key.
    private static let modifierKeys: [UInt16: String] = [
        55: "⌘ (left)", 54: "⌘ (right)",
        56: "⇧ (left)", 60: "⇧ (right)",
        58: "⌥ (left)", 61: "⌥ (right)",
        59: "⌃ (left)", 62: "⌃ (right)",
    ]

    private static let specialKeys: [UInt16: String] = [
        48: "⇥", 49: "Space", 36: "↩", 76: "⌤", 53: "⎋", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let printableKeys: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 32: "U", 34: "I",
        31: "O", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/", 10: "§",
    ]
}
