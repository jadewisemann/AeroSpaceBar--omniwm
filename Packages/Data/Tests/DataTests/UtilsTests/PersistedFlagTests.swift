// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Combine
@testable import Data
import Domain
import Nimble
import XCTest

/// Tests for `PersistedFlag`.
final class PersistedFlagTests: XCTestCase {
    /// Name of the isolated UserDefaults suite used by the tests.
    private let suiteName = "com.rdrkr.AeroSpaceBar.PersistedFlagTests"

    /// The isolated UserDefaults store used by the tests.
    private var userDefaults: UserDefaults?

    /// Subscriptions kept alive for the duration of a test.
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        cancellables.removeAll()
        UserDefaults().removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testInitialValueIsReadFromUserDefaults() {
        guard let userDefaults else {
            fail("UserDefaults not initialized")
            return
        }

        // Given a stored value
        userDefaults.set(true, forKey: UserDefaultsKeys.hasAskedForAccessibilityPermissions.rawValue)

        // When creating the flag
        let flag = PersistedFlag(key: .hasAskedForAccessibilityPermissions, userDefaults: userDefaults)
        var received: [Bool] = []
        flag.publisher.sink { received.append($0) }.store(in: &cancellables)

        // Then it emits the stored value
        expect(received) == [true]
    }

    func testSetPersistsAndEmitsOnlyChanges() {
        guard let userDefaults else {
            fail("UserDefaults not initialized")
            return
        }

        // Given a flag with no stored value
        let flag = PersistedFlag(key: .hasAskedForAccessibilityPermissions, userDefaults: userDefaults)
        var received: [Bool] = []
        flag.publisher.sink { received.append($0) }.store(in: &cancellables)

        // When setting the same value twice
        flag.set(true)
        flag.set(true)

        // Then the value is persisted and emitted once
        expect(userDefaults.bool(forKey: UserDefaultsKeys.hasAskedForAccessibilityPermissions.rawValue)) == true
        expect(received) == [false, true]
    }
}
