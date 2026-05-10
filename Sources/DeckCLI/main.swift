import DeckCore
import Darwin
import Foundation

private let usage = """
    USAGE: deck <command> [args]

    COMMANDS:
      init <name> [--root <path>] [--force]     Create a starter profile
      list                                      List profiles in ~/.config/deck/profiles
      path <name-or-path>                       Print the resolved profile path
      check <name-or-path>                      Parse and validate a profile
      open <name-or-path> [--no-winmux]         Launch a profile and route windows through WinMux
           [--dry-run] [--verbose]
      edit <name-or-path>                       Open a profile in $EDITOR or TextEdit
      example                                   Print an example profile

    Deck profiles are TOML files. By name, Deck reads ~/.config/deck/profiles/<name>.toml.
    """

@main
struct DeckMain {
    static func main() async {
        do {
            try await run()
        } catch let error as DeckError {
            exit(1, err: error.description)
        } catch {
            exit(1, err: error.localizedDescription)
        }
    }

    private static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            exit(1, err: usage)
        }
        args.removeFirst()
        if command == "-h" || command == "--help" || command == "help" {
            exit(0, out: usage)
        }

        let storage = DeckStorage()
        switch command {
            case "init":
                let flags = FlagParser(args)
                let name = try flags.requiredPositional("name")
                let root = flags.value("--root")
                let force = flags.has("--force")
                try flags.assertNoUnknownFlags(allowed: ["--root", "--force"])
                let url = try storage.createStarterProfile(name: name, root: root, force: force)
                exit(0, out: "Created \(url.path)")

            case "list":
                let profiles = try storage.listProfiles()
                if profiles.isEmpty {
                    exit(0, out: "No Deck profiles found in \(storage.profilesDirectory.path)")
                }
                exit(0, out: profiles.map { "\($0.name)\t\($0.url.path)" }.joined(separator: "\n"))

            case "path":
                let flags = FlagParser(args)
                let name = try flags.requiredPositional("name-or-path")
                try flags.assertNoUnknownFlags()
                exit(0, out: storage.profileUrl(for: name).path)

            case "check":
                let flags = FlagParser(args)
                let argument = try flags.requiredPositional("name-or-path")
                try flags.assertNoUnknownFlags()
                _ = try storage.loadProfile(argument)
                exit(0, out: "OK")

            case "open":
                let flags = FlagParser(args)
                let argument = try flags.requiredPositional("name-or-path")
                let profileUrl = storage.profileUrl(for: argument)
                let profile = try DeckProfileParser.parseFile(profileUrl)
                try flags.assertNoUnknownFlags(allowed: ["--no-winmux", "--dry-run", "--verbose"])
                let options = DeckOpenOptions(
                    enableWinMuxRouting: !flags.has("--no-winmux"),
                    dryRun: flags.has("--dry-run"),
                    verbose: flags.has("--verbose"),
                )
                let report = try await DeckRunner().open(profile: profile, profileUrl: profileUrl, options: options)
                exit(0, out: formatOpenReport(profile: profile, report: report, dryRun: options.dryRun))

            case "edit":
                let flags = FlagParser(args)
                let argument = try flags.requiredPositional("name-or-path")
                try flags.assertNoUnknownFlags()
                let url = storage.profileUrl(for: argument)
                try openEditor(url: url)
                exit(0)

            case "example":
                exit(0, out: DeckStorage.starterProfile(name: "winmux", root: "$HOME/Projects/WindowManagers/winmux"))

            default:
                throw DeckError.invalidArguments("Unknown Deck command '\(command)'.\n\n\(usage)")
        }
    }
}

private final class FlagParser {
    private let rawArgs: [String]

    init(_ rawArgs: [String]) {
        self.rawArgs = rawArgs
    }

    func has(_ flag: String) -> Bool {
        rawArgs.contains(flag)
    }

    func value(_ flag: String) -> String? {
        guard let index = rawArgs.firstIndex(of: flag), rawArgs.indices.contains(index + 1) else { return nil }
        return rawArgs[index + 1]
    }

    func requiredPositional(_ label: String) throws -> String {
        if let positional = positionals.first {
            return positional
        }
        throw DeckError.invalidArguments("Missing \(label).\n\n\(usage)")
    }

    func assertNoUnknownFlags(allowed: [String] = []) throws {
        let allowedFlags = Set(allowed)
        for arg in rawArgs where arg.hasPrefix("-") && !allowedFlags.contains(arg) {
            throw DeckError.invalidArguments("Unknown flag '\(arg)'.")
        }
        if let rootIndex = rawArgs.firstIndex(of: "--root"), !rawArgs.indices.contains(rootIndex + 1) {
            throw DeckError.invalidArguments("--root requires a value.")
        }
    }

    private var positionals: [String] {
        var result: [String] = []
        var skipNext = false
        for arg in rawArgs {
            if skipNext {
                skipNext = false
                continue
            }
            if arg == "--root" {
                skipNext = true
                continue
            }
            if arg.hasPrefix("-") { continue }
            result.append(arg)
        }
        return result
    }
}

private func formatOpenReport(profile: DeckProfile, report: DeckOpenReport, dryRun: Bool) -> String {
    var lines: [String] = []
    lines.append("\(dryRun ? "Would open" : "Opened") Deck '\(profile.name)'")
    if !report.launchedActions.isEmpty {
        lines.append("Actions: \(report.launchedActions.joined(separator: ", "))")
    }
    if dryRun {
        lines.append("Routing: dry run")
        return lines.joined(separator: "\n")
    }
    if let skippedRoutingReason = report.skippedRoutingReason {
        lines.append("Routing skipped: \(skippedRoutingReason)")
    } else if report.routeOperationCount > 0 {
        lines.append("Routed \(report.routedWindowIds.count) window(s) with \(report.routeOperationCount) WinMux operation(s)")
    } else if profile.actions.contains(where: { $0.route != nil }) {
        lines.append("No matching windows were routed")
    }
    return lines.joined(separator: "\n")
}

private func openEditor(url: URL) throws {
    let editor = ProcessInfo.processInfo.environment["EDITOR"]
    let process = Process()
    if let editor, !editor.isEmpty {
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", "\(editor) \(DeckShell.quote(url.path))"]
    } else {
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = ["-a", "TextEdit", url.path]
    }
    try process.run()
}

private func exit(_ code: Int32, out: String = "", err: String = "") -> Never {
    if !out.isEmpty {
        print(out)
    }
    if !err.isEmpty {
        fputs(err + "\n", stderr)
    }
    Darwin.exit(code)
}
