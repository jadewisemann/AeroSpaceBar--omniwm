// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Combine
import Domain
import Foundation

/// A Boolean value persisted in `UserDefaults` and exposed as a Combine publisher.
///
/// Used for internal markers, such as whether a system permission prompt has been shown,
/// that belong in UserDefaults rather than in the TOML configuration file.
final class PersistedFlag {
    /// The UserDefaults key the value is stored under.
    private let key: UserDefaultsKeys

    /// The UserDefaults store backing the flag.
    private let userDefaults: UserDefaults

    /// Subject holding the current value.
    private let subject: CurrentValueSubject<Bool, Never>

    /// Creates a flag initialized from the value currently stored in UserDefaults.
    /// - Parameters:
    ///   - key: The UserDefaults key the value is stored under.
    ///   - userDefaults: The UserDefaults store backing the flag.
    init(key: UserDefaultsKeys, userDefaults: UserDefaults = .standard) {
        self.key = key
        self.userDefaults = userDefaults
        subject = CurrentValueSubject(userDefaults.bool(forKey: key.rawValue))
    }

    /// Publisher that emits the current value and every subsequent change.
    var publisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Persists a new value and emits it if it differs from the current one.
    /// - Parameter value: The new value.
    func set(_ value: Bool) {
        guard value != subject.value else { return }

        userDefaults.set(value, forKey: key.rawValue)
        subject.send(value)
    }
}
