// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Combine
import Domain
import Foundation

/// Permission request tracking for `ConfigurationRepository`.
///
/// These markers record whether a system permission prompt has been shown. They are stored in
/// UserDefaults rather than the TOML configuration because they are not user-facing settings.
public extension ConfigurationRepository {
    /// Publisher that emits whether the user has been asked for screen capture permissions.
    var hasAskedForScreenCapturePermissionsPublisher: AnyPublisher<Bool, Never> {
        hasAskedForScreenCapturePermissionsFlag.publisher
    }

    /// Publisher that emits whether the user has been asked for Accessibility permissions.
    var hasAskedForAccessibilityPermissionsPublisher: AnyPublisher<Bool, Never> {
        hasAskedForAccessibilityPermissionsFlag.publisher
    }

    /// Sets whether the user has been asked for screen capture permissions.
    /// - Parameter value: Whether the screen capture permission prompt has been shown
    func setHasAskedForScreenCapturePermissions(_ value: Bool) {
        hasAskedForScreenCapturePermissionsFlag.set(value)
    }

    /// Sets whether the user has been asked for Accessibility permissions.
    /// - Parameter value: Whether the Accessibility permission prompt has been shown
    func setHasAskedForAccessibilityPermissions(_ value: Bool) {
        hasAskedForAccessibilityPermissionsFlag.set(value)
    }
}
