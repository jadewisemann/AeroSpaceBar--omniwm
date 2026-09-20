// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Darwin
@testable import Data
import Foundation
import Testing

@Suite("OmniWM CLI transport")
struct OmniWMClientTests {
    private func script(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("omniwmctl")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @Test
    func `Already-focused no_change responses are successful actions`() async throws {
        let url = try script("echo '{\"ok\":false,\"code\":\"no_change\"}'; exit 1\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let output = try await OmniWMClient().execute(executablePath: url.path, arguments: [])
        #expect(!output.isEmpty)
    }

    @Test
    func `Transport and authorization failures are surfaced`() async throws {
        let url = try script("echo '{\"ok\":false,\"code\":\"unauthorized\"}'; exit 1\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await #expect(throws: OmniWMError.self) {
            try await OmniWMClient().execute(executablePath: url.path, arguments: [])
        }
    }

    @Test
    func `Events preserve partial lines and multiple envelopes per read`() async throws {
        let url = try script("""
        printf '{"ok":true,'
        sleep 0.05
        printf '"kind":"subscribe"}\\n{"ok":true,"kind":"event"}\\n'
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var lines: [String] = []
        for try await line in OmniWMClient().events(executablePath: url.path) {
            try lines.append(#require(String(data: line, encoding: .utf8)))
        }
        #expect(lines == [#"{"ok":true,"kind":"subscribe"}"#, #"{"ok":true,"kind":"event"}"#])
    }

    @Test
    func `A missing executable fails promptly`() async {
        await #expect(throws: (any Error).self) {
            try await OmniWMClient().execute(executablePath: "/nonexistent/omniwmctl", arguments: [])
        }
    }

    @Test
    func `Cancelling a subscription terminates its CLI process`() async throws {
        let url = try script("echo $$ > \"$0.pid\"\nexec /bin/sleep 20\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let task = Task {
            for try await _ in OmniWMClient().events(executablePath: url.path) { }
        }
        defer { task.cancel() }
        let pidPath = url.path + ".pid"
        for _ in 0 ..< 100 where !FileManager.default.fileExists(atPath: pidPath) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let contents = try String(contentsOfFile: pidPath, encoding: .utf8)
        guard let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            Issue.record("CLI did not publish a valid PID")
            return
        }

        task.cancel()
        _ = try? await task.value
        for _ in 0 ..< 100 where kill(pid, 0) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(kill(pid, 0) == -1)
    }
}
