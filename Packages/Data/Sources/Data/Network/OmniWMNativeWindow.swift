// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import AppKit
import ApplicationServices
import Foundation

/// Accessibility has no public CGWindowID accessor. Match the exact window, never just its app or title.
@_silgen_name("_AXUIElementGetWindow")
private func accessibilityWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Visible macOS windows absent from OmniWM's managed-window query.
struct OmniWMNativeWindow: Sendable {
    let id: Int
    let pid: pid_t
    let appName: String
    let title: String
    let displayID: String?
    let isFocused: Bool

    @MainActor
    static func read(excluding managedIDs: Set<Int>) -> [Self] {
        guard
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]] else { return [] }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var focusedID: CGWindowID?
        return list.compactMap { info in
            guard
                let id = info[kCGWindowNumber as String] as? Int,
                !managedIDs.contains(id),
                info[kCGWindowLayer as String] as? Int == 0,
                let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let app = NSRunningApplication(processIdentifier: pid),
                app.activationPolicy != .prohibited
            else { return nil }

            if pid == frontmostPID, focusedID == nil {
                let application = applicationElement(pid)
                var value: CFTypeRef?
                if
                    unsafe AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
                    == .success,
                    let value, CFGetTypeID(value) == AXUIElementGetTypeID()
                {
                    focusedID = windowID(unsafe unsafeDowncast(value, to: AXUIElement.self))
                }
            }
            var displayID: String?
            if
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            {
                var display: CGDirectDisplayID = 0
                var count: UInt32 = 0
                if unsafe CGGetDisplaysWithRect(frame, 1, &display, &count) == .success, count > 0 {
                    displayID = "display:\(display)"
                }
            }
            return Self(
                id: id,
                pid: pid,
                appName: app.localizedName ?? "",
                title: info[kCGWindowName as String] as? String ?? "",
                displayID: displayID,
                isFocused: pid == frontmostPID && focusedID.map { Int($0) == id } == true
            )
        }
    }

    @MainActor
    func focus() throws {
        let application = Self.applicationElement(pid)
        var value: CFTypeRef?
        guard
            unsafe AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement],
            let window = windows.first(where: { Self.windowID($0).map { Int($0) == id } == true }),
            let app = NSRunningApplication(processIdentifier: pid)
        else { throw OmniWMError.missingWindow }

        app.activate()
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            throw OmniWMError.missingWindow
        }
    }

    private static func applicationElement(_ pid: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        return application
    }

    private static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var identifier: CGWindowID = 0
        return unsafe accessibilityWindowID(element, &identifier) == .success ? identifier : nil
    }
}
