// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Combine
@testable import Data
import Domain
import Foundation
import Testing

@Suite("OmniWM adapter")
@MainActor
struct OmniWMRepositoryTests {
    private static let workspaces = Data("""
    {"ok":true,"result":{"kind":"workspaces","payload":{"workspaces":[
      {"id":"uuid-2","rawName":"2","isCurrent":true,"isFocused":false,"isVisible":true},
      {"id":"uuid-1","rawName":"1","isCurrent":false,"isFocused":true,"isVisible":true}
    ]}}}
    """.utf8)

    private static let windows = Data("""
    {"ok":true,"result":{"kind":"windows","payload":{"windows":[
      {"id":"ow_session_b","windowId":42,"workspace":{"id":"uuid-1"},
       "app":{"name":"Safari"},"title":"Second","isFocused":false,"isVisible":false},
      {"id":"ow_session_a","windowId":12,"workspace":{"id":"uuid-1"},
       "app":{"name":"Terminal"},"title":"First","isFocused":true},
      {"id":"ow_scratchpad","windowId":99,"workspace":null,"title":null,"isFocused":false}
    ]}}}
    """.utf8)

    private func makeRepository(client: MockOmniWMClient, startMonitoring: Bool = false) -> OmniWMRepository {
        let configuration = MockConfigurationGateway()
        return OmniWMRepository(
            iconCache: MockIconCache(),
            getAeroSpacePathUseCase: GetAeroSpacePathUseCase(configurationGateway: configuration),
            getSpacesColorPropertiesUseCase: GetSpacesColorPropertiesUseCase(configurationGateway: configuration),
            client: client,
            startMonitoring: startMonitoring
        )
    }

    @Test
    func `Preserves empty/current workspaces, all managed windows, and stable CGWindowIDs`() throws {
        let decoder = JSONDecoder()
        let snapshot = try OmniWMSnapshot(
            workspaces: decoder.decode(OmniWMResponse<OmniWMWorkspaces>.self, from: Self.workspaces).payload(),
            windows: decoder.decode(OmniWMResponse<OmniWMWindows>.self, from: Self.windows).payload()
        )
        let spaces = snapshot.spaces()
        #expect(spaces.map(\.id) == ["1", "2"])
        #expect(spaces[0].windows.map(\.id) == [12, 42])
        #expect(spaces[0].windows[0].isFocused)
        #expect(!spaces[0].isFocused)
        #expect(spaces[1].isFocused)
        #expect(spaces[1].windows.isEmpty)
        #expect(snapshot.windowTargets["42"] == "ow_session_b")
    }

    @Test
    func `Clicks use opaque session IDs and raw workspace names`() async throws {
        let client = MockOmniWMClient(workspaces: Self.workspaces, windows: Self.windows)
        let repository = makeRepository(client: client)
        await repository.refresh()
        try await repository.focusWindow(windowId: "42")
        try await repository.focusSpace(spaceId: "2", needWindowFocus: true)
        let commands = await client.commands
        #expect(commands.contains(["window", "navigate", "ow_session_b", "--json"]))
        #expect(commands.contains(["workspace", "focus-name", "2", "--json"]))
    }

    @Test
    func `Unchanged refreshes do not trigger extra UI updates`() async {
        let client = MockOmniWMClient(workspaces: Self.workspaces, windows: Self.windows)
        let repository = makeRepository(client: client)
        var snapshots: [[Space]] = []
        let subscription = repository.spacesWithWindowsPublisher.sink { snapshots.append($0) }
        await repository.refresh()
        await repository.refresh()
        #expect(snapshots.count == 2) // Initial empty value and one populated snapshot.
        subscription.cancel()
    }

    @Test
    func `Failed refresh invalidates old session IDs and recovers on the next snapshot`() async throws {
        let client = MockOmniWMClient(workspaces: Self.workspaces, windows: Self.windows)
        let repository = makeRepository(client: client)
        var states: [Bool] = []
        let subscription = repository.aeroSpaceRunningPublisher.sink { states.append($0) }
        await repository.refresh()
        await client.setFailure(true)
        await repository.refresh()
        do {
            try await repository.focusWindow(windowId: "42")
            Issue.record("A stale window ID must not be sent after disconnect")
        } catch { }
        let windowJSON = try #require(String(data: Self.windows, encoding: .utf8))
        await client.replaceWindows(Data(
            windowJSON.replacingOccurrences(of: "ow_session_b", with: "ow_new_session_b").utf8
        ))
        await client.setFailure(false)
        await repository.refresh()
        try await repository.focusWindow(windowId: "42")
        #expect(states == [false, true, false, true])
        let lastCommand = await client.commands.last
        #expect(lastCommand == ["window", "navigate", "ow_new_session_b", "--json"])
        subscription.cancel()
    }

    @Test
    func `IPC failures and malformed snapshots are not accepted as empty workspaces`() throws {
        let data = Data(#"{"ok":false,"code":"unauthorized"}"#.utf8)
        let response = try JSONDecoder().decode(OmniWMResponse<OmniWMWorkspaces>.self, from: data)
        #expect(throws: OmniWMError.self) { try response.payload() }
        let malformed = Data(#"{"ok":true,"result":{"payload":{"workspaces":[{"id":"1"}]}}}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(OmniWMResponse<OmniWMWorkspaces>.self, from: malformed)
        }
    }

    @Test
    func `A dropped event subscription reconnects and resynchronizes`() async throws {
        let client = MockOmniWMClient(workspaces: Self.workspaces, windows: Self.windows)
        let repository = makeRepository(client: client, startMonitoring: true)
        var states: [Bool] = []
        let subscription = repository.aeroSpaceRunningPublisher.sink { states.append($0) }
        for _ in 0 ..< 100 where states.last != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(states.last == true)
        await client.setFailure(true)
        await client.disconnect()
        for _ in 0 ..< 100 where states.last != false {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(states.last == false)
        await client.setFailure(false)
        for _ in 0 ..< 300 {
            if await client.subscriptionCount >= 2, states.last == true {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let count = await client.subscriptionCount
        #expect(count >= 2)
        #expect(states.last == true)
        subscription.cancel()
    }
}

private actor MockOmniWMClient: OmniWMClientProtocol {
    let workspaces: Data
    var windows: Data
    var commands: [[String]] = []
    var failure = false
    var subscriptionCount = 0
    var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    init(workspaces: Data, windows: Data) {
        self.workspaces = workspaces
        self.windows = windows
    }

    func setFailure(_ value: Bool) {
        failure = value
    }

    func replaceWindows(_ value: Data) {
        windows = value
    }

    func disconnect() {
        continuation?.finish()
    }

    func subscribe(_ continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        subscriptionCount += 1
        self.continuation = continuation
        continuation.yield(Data(#"{"ok":true,"kind":"event"}"#.utf8))
    }

    func execute(executablePath _: String, arguments: [String]) throws -> Data {
        commands.append(arguments)
        if failure {
            throw OmniWMError.requestFailed("transport_failure")
        }
        if arguments == ["query", "workspaces"] {
            return workspaces
        }
        if arguments == ["query", "windows"] {
            return windows
        }
        return Data(#"{"ok":true}"#.utf8)
    }

    nonisolated func events(executablePath _: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.subscribe(continuation) }
        }
    }
}
