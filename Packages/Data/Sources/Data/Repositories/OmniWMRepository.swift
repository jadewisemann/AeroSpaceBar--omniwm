// Copyright (c) 2026 AeroSpaceBar by Ronen Druker.

import AppKit
import Combine
import Domain
import Foundation

/// Supplies OmniWM state to the original spaces UI, preserving its rendering and animation pipeline.
@MainActor
public final class OmniWMRepository: SpacesGateway {
    private let client: OmniWMClientProtocol
    private let iconCache: IconCacheProtocol
    private let commandExecutor: CommandExecutorProtocol
    private let runningAppChecker: RunningAppCheckerProtocol
    private var executablePath: String
    private var colors: [ColorProperties] = []
    private var windowTargets: [String: String] = [:]
    private var nativeWindowTargets: [String: OmniWMNativeWindow] = [:]
    var nativeWindowProvider: @MainActor (Set<Int>) -> [OmniWMNativeWindow] = OmniWMNativeWindow.read
    private var cancellables: Set<AnyCancellable> = []
    private var eventTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var refreshing = false
    private var refreshAgain = false
    private var generation = 0
    private let spacesSubject = CurrentValueSubject<[Space], Never>([])
    private let runningSubject = CurrentValueSubject<Bool, Never>(false)

    /// Emits only changed snapshots, just like the original repository.
    public var spacesWithWindowsPublisher: AnyPublisher<[Space], Never> {
        spacesSubject.removeDuplicates().eraseToAnyPublisher()
    }

    /// The existing gateway name is retained for presentation compatibility; this reports OmniWM IPC availability.
    public var aeroSpaceRunningPublisher: AnyPublisher<Bool, Never> {
        runningSubject.removeDuplicates().eraseToAnyPublisher()
    }

    /// Creates the OmniWM backend with the existing path and appearance preferences.
    public init(
        iconCache: IconCacheProtocol,
        getAeroSpacePathUseCase: GetAeroSpacePathUseCase,
        getSpacesColorPropertiesUseCase: GetSpacesColorPropertiesUseCase,
        client: OmniWMClientProtocol = OmniWMClient(),
        commandExecutor: CommandExecutorProtocol = CommandExecutor(),
        runningAppChecker: RunningAppCheckerProtocol = RunningAppChecker(),
        startMonitoring: Bool = true
    ) {
        self.iconCache = iconCache
        self.client = client
        self.commandExecutor = commandExecutor
        self.runningAppChecker = runningAppChecker
        executablePath = getAeroSpacePathUseCase.execute().blockingFirst()
        colors = getSpacesColorPropertiesUseCase.execute().blockingFirst()

        getAeroSpacePathUseCase.execute()
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] path in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    executablePath = path
                    generation += 1
                    windowTargets = [:]
                    nativeWindowTargets = [:]
                    if startMonitoring {
                        monitor()
                    }
                }
            }
            .store(in: &cancellables)

        getSpacesColorPropertiesUseCase.execute()
            .dropFirst()
            .sink { [weak self] colors in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    self.colors = colors
                    publish(spacesSubject.value)
                }
            }
            .store(in: &cancellables)

        if startMonitoring {
            let center = NSWorkspace.shared.notificationCenter
            for name in [
                NSWorkspace.didActivateApplicationNotification,
                NSWorkspace.didTerminateApplicationNotification,
                NSWorkspace.didHideApplicationNotification,
                NSWorkspace.didUnhideApplicationNotification
            ] {
                center.publisher(for: name)
                    .sink { [weak self] _ in
                        Task { @MainActor [weak self] in self?.scheduleRefresh() }
                    }
                    .store(in: &cancellables)
            }
            monitor()
        }
    }

    deinit {
        eventTask?.cancel()
        refreshTask?.cancel()
        pollTask?.cancel()
    }

    /// Focuses a workspace by its stable raw name, including empty workspaces.
    public func focusSpace(spaceId: String, needWindowFocus _: Bool) async throws {
        _ = try await client.execute(
            executablePath: executablePath,
            arguments: ["workspace", "focus-name", spaceId, "--json"]
        )
        scheduleRefresh()
    }

    /// Navigates to a window using its session-scoped OmniWM ID, switching workspaces when needed.
    public func focusWindow(windowId: String) async throws {
        if let window = nativeWindowTargets[windowId] {
            try window.focus()
            scheduleRefresh()
            return
        }
        guard let target = windowTargets[windowId] else { throw OmniWMError.missingWindow }

        _ = try await client.execute(
            executablePath: executablePath,
            arguments: ["window", "navigate", target, "--json"]
        )
        scheduleRefresh()
    }

    /// Launches OmniWM. IPC must be enabled by the user in OmniWM's menu.
    public func startAeroSpace() async throws {
        guard !runningAppChecker.isRunning(name: "OmniWM") else { return }

        try await commandExecutor.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", "OmniWM"]
        )
        scheduleRefresh()
    }

    /// Refreshes atomically and serially so older requests cannot overwrite a newer state.
    func refresh() async {
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        defer {
            refreshing = false
            if refreshAgain {
                refreshAgain = false
                scheduleRefresh()
            }
        }
        let requestGeneration = generation
        let path = executablePath
        do {
            async let workspaceData = client.execute(
                executablePath: path, arguments: ["query", "workspaces"]
            )
            async let windowData = client.execute(
                executablePath: path, arguments: ["query", "windows"]
            )
            let decoder = JSONDecoder()
            let workspaces = try await decoder.decode(
                OmniWMResponse<OmniWMWorkspaces>.self, from: workspaceData
            )
            .payload()
            let windows = try await decoder.decode(
                OmniWMResponse<OmniWMWindows>.self, from: windowData
            )
            .payload()
            guard requestGeneration == generation, !Task.isCancelled else { return }

            let snapshot = OmniWMSnapshot(workspaces: workspaces, windows: windows)
            let nativeWindows = nativeWindowProvider(Set(windows.windows.map(\.windowId)))
            windowTargets = snapshot.windowTargets
            nativeWindowTargets = Dictionary(
                nativeWindows.map { (String($0.id), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            publish(snapshot.spaces(nativeWindows: nativeWindows))
            runningSubject.send(true)
        } catch {
            guard requestGeneration == generation, !Task.isCancelled else { return }

            disconnected()
            Logger.warning("OmniWM refresh failed: \(error.localizedDescription)", category: Logger.spaces)
        }
    }

    private func publish(_ spaces: [Space]) {
        var spaces = spaces.sorted { $0.id < $1.id }
        for index in spaces.indices {
            spaces[index].colorProperties = index < colors.count
                ? colors[index] : ConfigurationDefaults.spaceColorProperties
            for windowIndex in spaces[index].windows.indices {
                if let name = spaces[index].windows[windowIndex].appName {
                    spaces[index].windows[windowIndex].appIcon = iconCache.icon(for: name)
                }
            }
        }
        spacesSubject.send(spaces)
    }

    private func disconnected() {
        generation += 1
        windowTargets = [:]
        nativeWindowTargets = [:]
        runningSubject.send(false)
    }

    private func scheduleRefresh() {
        // Start immediately; refresh() folds signals received during I/O into one follow-up request.
        if refreshing {
            refreshAgain = true
            return
        }
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard !Task.isCancelled else { return }

            self?.refreshTask = nil
            await self?.refresh()
        }
    }

    /// Applies the interaction workspace before querying the full window list.
    func receiveEvent(_ data: Data) {
        if
            let response = try? JSONDecoder().decode(OmniWMResponse<OmniWMActiveWorkspace>.self, from: data),
            response.ok, response.channel == "active-workspace",
            let workspace = response.result?.payload.workspace,
            spacesSubject.value.contains(where: { $0.id == workspace.rawName })
        {
            // An in-flight snapshot predates this event and must not restore the previous selection.
            generation += 1
            var spaces = spacesSubject.value
            for index in spaces.indices {
                spaces[index].isFocused = spaces[index].id == workspace.rawName
                if !spaces[index].isFocused {
                    for windowIndex in spaces[index].windows.indices {
                        spaces[index].windows[windowIndex].isFocused = false
                    }
                }
            }
            spacesSubject.send(spaces)
        }
        scheduleRefresh()
    }

    private func monitor() {
        eventTask?.cancel()
        pollTask?.cancel()
        let path = executablePath
        let client = client
        eventTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    for try await event in client.events(executablePath: path) {
                        guard !Task.isCancelled else { return }

                        self?.receiveEvent(event)
                    }
                } catch {
                    Logger.debug("OmniWM event stream disconnected", category: Logger.spaces)
                }
                guard !Task.isCancelled else { return }

                self?.disconnected()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
}
