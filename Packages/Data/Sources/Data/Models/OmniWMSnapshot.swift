// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Domain
import Foundation

/// The CLI envelope is shared by queries, commands, and subscription events.
struct OmniWMResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    struct Result: Decodable, Sendable {
        let payload: Payload
    }

    let ok: Bool
    let code: String?
    let result: Result?

    func payload() throws -> Payload {
        guard ok, let result else {
            throw OmniWMError.requestFailed(code)
        }

        return result.payload
    }
}

enum OmniWMError: LocalizedError {
    case requestFailed(String?)
    case missingWindow

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            String(localized: LocalizedStringResource(
                "Cannot communicate with OmniWM. Make sure OmniWM is running and Enable IPC is turned on."
            ))

        case .missingWindow:
            String(localized: LocalizedStringResource("This window is no longer available in OmniWM."))
        }
    }
}

struct OmniWMWorkspaces: Decodable, Sendable {
    struct Workspace: Decodable, Sendable {
        let id: String
        let rawName: String
        let isCurrent: Bool
    }

    let workspaces: [Workspace]
}

struct OmniWMWindows: Decodable, Sendable {
    struct Workspace: Decodable, Sendable {
        let id: String
    }

    struct App: Decodable, Sendable {
        let name: String
    }

    struct Window: Decodable, Sendable {
        let id: String
        let windowId: Int
        let workspace: Workspace?
        let app: App?
        let title: String?
        let isFocused: Bool
    }

    let windows: [Window]
}

/// Translates OmniWM state without changing the existing presentation models or their identity.
struct OmniWMSnapshot: Sendable {
    let workspaces: OmniWMWorkspaces
    let windows: OmniWMWindows

    var windowTargets: [String: String] {
        windows.windows.reduce(into: [:]) { $0[String($1.windowId)] = $1.id }
    }

    func spaces() -> [Space] {
        let grouped = Dictionary(grouping: windows.windows, by: { $0.workspace?.id })
        return workspaces.workspaces
            .map { workspace in
                Space(
                    id: workspace.rawName,
                    isFocused: workspace.isCurrent,
                    windows: (grouped[workspace.id] ?? [])
                        .map { window in
                            Window(
                                id: window.windowId,
                                title: window.title ?? "",
                                appName: window.app?.name,
                                isFocused: window.isFocused,
                                workspace: workspace.rawName
                            )
                        }
                        .sorted { $0.id < $1.id }
                )
            }
            .sorted { $0.id < $1.id }
    }
}

struct OmniWMVersion: Decodable, Sendable {
    let appVersion: String?
}
