import Foundation

public struct DeckOpenOptions: Sendable {
    public var enableWinMuxRouting: Bool
    public var dryRun: Bool
    public var verbose: Bool

    public init(enableWinMuxRouting: Bool = true, dryRun: Bool = false, verbose: Bool = false) {
        self.enableWinMuxRouting = enableWinMuxRouting
        self.dryRun = dryRun
        self.verbose = verbose
    }
}

public struct DeckOpenReport: Equatable, Sendable {
    public var launchedActions: [String]
    public var skippedRoutingReason: String?
    public var routedWindowIds: [UInt32]
    public var routeOperationCount: Int

    public init(
        launchedActions: [String] = [],
        skippedRoutingReason: String? = nil,
        routedWindowIds: [UInt32] = [],
        routeOperationCount: Int = 0,
    ) {
        self.launchedActions = launchedActions
        self.skippedRoutingReason = skippedRoutingReason
        self.routedWindowIds = routedWindowIds
        self.routeOperationCount = routeOperationCount
    }
}

public struct DeckRunner: Sendable {
    private let processRunner: any DeckProcessRunning
    private let winMuxClient: WinMuxAgentClient

    public init(
        processRunner: any DeckProcessRunning = DeckSystemProcessRunner(),
        winMuxClient: WinMuxAgentClient = WinMuxAgentClient(),
    ) {
        self.processRunner = processRunner
        self.winMuxClient = winMuxClient
    }

    public func open(
        profile: DeckProfile,
        profileUrl: URL? = nil,
        options: DeckOpenOptions = DeckOpenOptions(),
    ) async throws -> DeckOpenReport {
        let resolver = DeckVariableResolver(profile: profile, profileUrl: profileUrl)
        let root = profile.root.map { resolver.expand($0) }.map(DeckPath.expandTilde)
        var report = DeckOpenReport()

        let beforeSnapshot: DeckAgentSnapshot?
        if options.enableWinMuxRouting, profile.actions.contains(where: { $0.route != nil }), !options.dryRun {
            beforeSnapshot = try? await winMuxClient.query()
            if beforeSnapshot == nil {
                report.skippedRoutingReason = "WinMux is not running or agent query failed."
            }
        } else {
            beforeSnapshot = nil
        }

        for (index, action) in profile.actions.enumerated() {
            let label = action.name ?? "action \(index + 1)"
            if options.dryRun {
                report.launchedActions.append(label)
                continue
            }
            try await run(action: action, resolver: resolver, root: root)
            report.launchedActions.append(label)
        }

        guard options.enableWinMuxRouting, !options.dryRun else { return report }
        guard beforeSnapshot != nil else { return report }

        let maxTimeout = profile.actions
            .compactMap { $0.route?.timeoutSeconds }
            .max() ?? 0
        let afterSnapshot = try await waitForRoutableWindows(
            profile: profile,
            before: beforeSnapshot,
            timeoutSeconds: maxTimeout,
        )
        let (operations, summary) = DeckRoutingPlanner.plan(
            profile: profile,
            before: beforeSnapshot,
            after: afterSnapshot,
        )
        try await winMuxClient.apply(operations: operations, worldId: afterSnapshot.worldId)
        report.routedWindowIds = summary.routedWindowIds
        report.routeOperationCount = summary.operationsCount
        return report
    }

    private func run(action: DeckAction, resolver: DeckVariableResolver, root: String?) async throws {
        let type = try action.resolvedType()
        let environment = resolver.variables
        let cwd = action.cwd.map { DeckPath.absolutize(resolver.expand($0), relativeTo: root) } ?? root
        switch type {
            case .shell:
                let command = resolver.expand(action.run ?? "")
                try await runChecked("/bin/zsh", ["-lc", command], environment: environment, cwd: cwd, wait: action.wait)
            case .app:
                var args: [String] = []
                if let app = action.app {
                    args += ["-a", resolver.expand(app)]
                } else if let bundleId = action.bundleId {
                    args += ["-b", resolver.expand(bundleId)]
                }
                args += action.paths.map { DeckPath.absolutize(resolver.expand($0), relativeTo: root) }
                args += action.urls.map { resolver.expand($0) }
                try await runChecked("/usr/bin/open", args, environment: environment, cwd: cwd, wait: true)
            case .url:
                try await runChecked(
                    "/usr/bin/open",
                    action.urls.map { resolver.expand($0) },
                    environment: environment,
                    cwd: cwd,
                    wait: true,
                )
            case .file:
                try await runChecked(
                    "/usr/bin/open",
                    action.paths.map { DeckPath.absolutize(resolver.expand($0), relativeTo: root) },
                    environment: environment,
                    cwd: cwd,
                    wait: true,
                )
            case .browser:
                let app = resolver.expand(action.app ?? "Google Chrome")
                let urls = action.urls.map { resolver.expand($0) }
                var args = ["-a", app]
                if action.newWindow || action.profile != nil {
                    args += ["--args"]
                    if action.newWindow { args += ["--new-window"] }
                    if let profile = action.profile {
                        args += ["--profile-directory=\(resolver.expand(profile))"]
                    }
                    args += urls
                } else {
                    args += urls
                }
                try await runChecked("/usr/bin/open", args, environment: environment, cwd: cwd, wait: true)
            case .terminal:
                let terminalApp = resolver.expand(action.app ?? "Terminal")
                let command = resolver.expand(action.command ?? "")
                let terminalCwd = action.cwd.map { DeckPath.absolutize(resolver.expand($0), relativeTo: root) } ?? root
                let script = terminalAppleScript(app: terminalApp, cwd: terminalCwd, command: command)
                try await runChecked("/usr/bin/osascript", ["-e", script], environment: environment, cwd: cwd, wait: true)
            case .bunch:
                let bunchName = action.run ?? action.name ?? ""
                guard let encoded = resolver.expand(bunchName).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                    throw DeckError.invalidProfile("Unable to URL-encode Bunch name '\(bunchName)'.")
                }
                try await runChecked("/usr/bin/open", ["x-bunch://open?bunch=\(encoded)"], environment: environment, cwd: cwd, wait: true)
        }
    }

    private func runChecked(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String],
        cwd: String?,
        wait: Bool,
    ) async throws {
        let result = try await processRunner.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: cwd,
            wait: wait,
        )
        if result.exitCode != 0 {
            throw DeckError.commandFailed(
                """
                Command failed: \(executable) \(arguments.joined(separator: " "))
                Exit code: \(result.exitCode)
                \(result.stderr)
                """,
            )
        }
    }

    private func waitForRoutableWindows(
        profile: DeckProfile,
        before: DeckAgentSnapshot?,
        timeoutSeconds: Double,
    ) async throws -> DeckAgentSnapshot {
        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        var last = try await winMuxClient.query()
        var lastCandidateIds = DeckRoutingPlanner.routableCandidateWindowIds(
            profile: profile,
            before: before,
            after: last,
        )
        var lastCandidateChange = Date()
        while Date() < deadline {
            if DeckRoutingPlanner.hasCandidateForEveryRoutedAction(profile: profile, before: before, after: last) {
                return last
            }
            try await Task.sleep(nanoseconds: 350_000_000)
            last = try await winMuxClient.query()
            let candidateIds = DeckRoutingPlanner.routableCandidateWindowIds(
                profile: profile,
                before: before,
                after: last,
            )
            if candidateIds != lastCandidateIds {
                lastCandidateIds = candidateIds
                lastCandidateChange = Date()
            } else if !candidateIds.isEmpty, lastCandidateChange.distance(to: Date()) >= 1.0 {
                return last
            }
        }
        return last
    }

    private func terminalAppleScript(app: String, cwd: String?, command: String) -> String {
        let shellCommand: String
        if let cwd {
            shellCommand = "cd \(DeckShell.quote(cwd)) && \(command)"
        } else {
            shellCommand = command
        }
        if app.caseInsensitiveCompare("iTerm") == .orderedSame || app.caseInsensitiveCompare("iTerm2") == .orderedSame {
            return """
                tell application "iTerm"
                    activate
                    create window with default profile
                    tell current session of current window
                        write text "\(appleScriptEscaped(shellCommand))"
                    end tell
                end tell
                """
        }
        return """
            tell application "\(appleScriptEscaped(app))"
                activate
                do script "\(appleScriptEscaped(shellCommand))"
            end tell
            """
    }

    private func appleScriptEscaped(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
