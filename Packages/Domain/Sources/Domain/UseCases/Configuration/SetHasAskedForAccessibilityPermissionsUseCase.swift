// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Foundation

/// Use case for setting whether the user has been asked for Accessibility permissions.
@MainActor
public final class SetHasAskedForAccessibilityPermissionsUseCase {
    /// The gateway providing access to configuration values.
    private let configurationGateway: ConfigurationGateway

    /// Initializes the use case.
    /// - Parameter configurationGateway: The gateway providing access to configuration values
    public init(configurationGateway: ConfigurationGateway) {
        self.configurationGateway = configurationGateway
    }

    /// Executes the use case to set whether the user has been asked for Accessibility permissions.
    /// - Parameter value: The state indicating whether permissions have been requested
    public func execute(value: Bool) async {
        await configurationGateway.setHasAskedForAccessibilityPermissions(value)
    }
}
