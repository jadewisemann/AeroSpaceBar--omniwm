// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Foundation

/// CLI boundary, injectable for snapshot, command, and reconnect tests.
public protocol OmniWMClientProtocol: Sendable {
    /// Runs a single CLI request and returns its JSON envelope.
    func execute(executablePath: String, arguments: [String]) async throws -> Data
    /// Emits complete NDJSON event envelopes until disconnected or cancelled.
    func events(executablePath: String) -> AsyncThrowingStream<Data, Error>
}

/// Uses OmniWM's bundled CLI so socket discovery, authentication and protocol negotiation stay native.
public struct OmniWMClient: OmniWMClientProtocol {
    /// Creates a CLI client.
    public init() { }

    /// Resolves Homebrew, user-installed, and bundled CLI locations.
    public static func executablePath() -> String {
        let candidates = [
            "/opt/homebrew/bin/omniwmctl",
            "/usr/local/bin/omniwmctl",
            NSHomeDirectory() + "/.local/bin/omniwmctl",
            "/Applications/OmniWM.app/Contents/MacOS/omniwmctl",
            NSHomeDirectory() + "/Applications/OmniWM.app/Contents/MacOS/omniwmctl"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    /// Executes without blocking the UI, with a bounded lifetime for one-shot requests.
    public func execute(executablePath: String, arguments: [String]) async throws -> Data {
        let process = Self.process(executablePath: executablePath, arguments: arguments)
        let timeout = Task.detached {
            try await Task.sleep(for: .seconds(3))
            if process.isRunning {
                process.terminate()
            }
        }
        defer { timeout.cancel() }

        var output = Data()
        for try await chunk in Self.output(process: process) {
            output.append(chunk)
        }
        let response = try JSONDecoder().decode(OmniWMResponse<EmptyPayload>.self, from: output)
        // OmniWM returns exit 1 when an already-focused target needs no change.
        guard response.ok || response.code == "no_change" else {
            throw OmniWMError.requestFailed(response.code)
        }

        return output
    }

    /// Streams changes used by the bar, avoiding per-frame layout events; the repository reconnects.
    public func events(executablePath: String) -> AsyncThrowingStream<Data, Error> {
        let process = Self.process(
            executablePath: executablePath,
            arguments: ["subscribe", "focus,active-workspace,windows-changed,display-changed", "--format", "ndjson"]
        )
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    var buffer = Data()
                    for try await chunk in Self.output(process: process) {
                        buffer.append(chunk)
                        while let newline = buffer.firstIndex(of: 0x0A) {
                            let line = Data(buffer[..<newline])
                            buffer.removeSubrange(...newline)
                            if !line.isEmpty {
                                continuation.yield(line)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct EmptyPayload: Decodable, Sendable { }

    private static func process(executablePath: String, arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    private static func output(process: Process) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                let pipe = Pipe()
                process.standardOutput = pipe
                do {
                    try Task.checkCancellation()
                    try process.run()
                    // Cancellation can race process launch; check again after launch.
                    if Task.isCancelled {
                        process.terminate()
                    }
                    while true {
                        let chunk = pipe.fileHandleForReading.availableData
                        if chunk.isEmpty {
                            break
                        }
                        continuation.yield(chunk)
                    }
                    process.waitUntilExit()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}
