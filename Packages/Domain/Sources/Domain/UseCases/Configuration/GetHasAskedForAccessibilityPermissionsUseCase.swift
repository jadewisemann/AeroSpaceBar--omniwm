// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Combine
import Foundation

/// Use case for retrieving whether the user has been asked for Accessibility permissions.
///
/// Exposes a publisher of Bool reflecting the current state.
@MainActor
public final class GetHasAskedForAccessibilityPermissionsUseCase {
    /// The gateway providing access to configuration values.
    private let configurationGateway: ConfigurationGateway

    /// Initializes the use case.
    /// - Parameter configurationGateway: The gateway providing access to configuration values
    public init(configurationGateway: ConfigurationGateway) {
        self.configurationGateway = configurationGateway
    }

    /// Executes the use case to get whether the user has been asked for Accessibility permissions.
    /// - Returns: A publisher emitting whether the user has been asked for Accessibility permissions
    public func execute() -> AnyPublisher<Bool, Never> {
        configurationGateway.hasAskedForAccessibilityPermissionsPublisher
    }
}
