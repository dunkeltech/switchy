//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import ApplicationServices
import Foundation

/// Small, type-safe wrappers around the C-based Accessibility API.
enum AX {
    /// Reads an attribute as a generic `CFTypeRef` (nil on error/absence).
    static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (copyAttribute(element, attribute) as? Bool) ?? false
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copyAttribute(element, attribute) as? [AXUIElement]) ?? []
    }

    /// Sets a bool attribute (e.g. `kAXMinimizedAttribute`).
    @discardableResult
    static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFTypeRef) == .success
    }

    /// Performs an action (e.g. `kAXRaiseAction`).
    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// Reads the frame (position + size) of an AX window in global coordinates.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard
            let posValue = copyAttribute(element, kAXPositionAttribute as String),
            let sizeValue = copyAttribute(element, kAXSizeAttribute as String)
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}
