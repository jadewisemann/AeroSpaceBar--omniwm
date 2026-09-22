// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import Domain
import Foundation

/// The CLI envelope is shared by queries, commands, and subscription events.
struct OmniWMResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    struct Result: Decodable, Sendable {
        let payload: Payload
    }

    let ok: Bool
    let channel: String?
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
    case accessibilityPermissionRequired

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            String(localized: LocalizedStringResource(
                "Cannot communicate with OmniWM. Make sure OmniWM is running and Enable IPC is turned on."
            ))

        case .missingWindow:
            String(localized: LocalizedStringResource("This window is no longer available."))

        case .accessibilityPermissionRequired:
            String(localized: LocalizedStringResource("Enable Accessibility permission to focus this window."))
        }
    }
}

struct OmniWMWorkspaces: Decodable, Sendable {
    struct Display: Decodable, Sendable {
        let id: String
    }

    struct Workspace: Decodable, Sendable {
        let id: String
        let rawName: String
        let isCurrent: Bool
        let isVisible: Bool?
        let display: Display?
    }

    let workspaces: [Workspace]
}

struct OmniWMActiveWorkspace: Decodable, Sendable {
    struct Workspace: Decodable, Sendable {
        let rawName: String
    }

    let workspace: Workspace?
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

    func spaces(nativeWindows: [OmniWMNativeWindow] = []) -> [Space] {
        let grouped = Dictionary(grouping: windows.windows, by: { $0.workspace?.id })
        let managedIDs = Set(windows.windows.map(\.windowId))
        let nativeWindowFocused = nativeWindows.contains(where: \.isFocused)
        let nativeGrouped = Dictionary(grouping: nativeWindows.filter { !managedIDs.contains($0.id) }) { window in
            workspaces.workspaces
                .first { workspace in
                    workspace.isVisible == true && window.displayID != nil && workspace.display?.id == window.displayID
                }?.id ?? workspaces.workspaces.first(where: \.isCurrent)?.id
        }
        return workspaces.workspaces
            .map { workspace in
                Space(
                    id: workspace.rawName,
                    isFocused: workspace.isCurrent,
                    windows: ((grouped[workspace.id] ?? [])
                        .map { window in
                            Window(
                                id: window.windowId,
                                title: window.title ?? "",
                                appName: window.app?.name,
                                isFocused: window.isFocused && !nativeWindowFocused,
                                workspace: workspace.rawName
                            )
                        } + (nativeGrouped[workspace.id] ?? []).map { window in
                            Window(
                                id: window.id,
                                title: window.title,
                                appName: window.appName,
                                isFocused: window.isFocused,
                                workspace: workspace.rawName
                            )
                        })
                        .sorted { $0.id < $1.id }
                )
            }
            .sorted { $0.id < $1.id }
    }
}

struct OmniWMVersion: Decodable, Sendable {
    let appVersion: String?
}
