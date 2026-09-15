// Copyright (c) 2025 AeroSpaceBar by Ronen Druker.

import AppKit
import Foundation

/// Represents a system menu bar application.
///
/// This struct contains information about an application that has an icon
/// in the macOS system menu bar (e.g., clock, WiFi, battery, etc.).
public struct MenuBarApp: Identifiable, Equatable, Sendable {
    /// The unique identifier for the menu bar app.
    public let id: String

    /// The position/frame of the menu bar item.
    public let frame: CGRect

    /// Creates a menu bar app.
    /// - Parameters:
    ///   - id: The unique identifier for the menu bar app.
    ///   - frame: The position/frame of the menu bar item.
    public init(id: String, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}
