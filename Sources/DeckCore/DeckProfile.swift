import Foundation

public struct DeckProfile: Codable, Equatable, Sendable {
    public var name: String
    public var root: String?
    public var env: [String: String]
    public var actions: [DeckAction]

    public init(
        name: String,
        root: String? = nil,
        env: [String: String] = [:],
        actions: [DeckAction] = [],
    ) {
        self.name = name
        self.root = root
        self.env = env
        self.actions = actions
    }

    enum CodingKeys: String, CodingKey {
        case name
        case root
        case env
        case actions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        root = try container.decodeIfPresent(String.self, forKey: .root)
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        actions = try container.decodeIfPresent([DeckAction].self, forKey: .actions) ?? []
    }
}

public struct DeckAction: Codable, Equatable, Sendable {
    public var name: String?
    public var type: DeckActionType?
    public var run: String?
    public var app: String?
    public var bundleId: String?
    public var urls: [String]
    public var paths: [String]
    public var cwd: String?
    public var command: String?
    public var profile: String?
    public var newWindow: Bool
    public var wait: Bool
    public var route: DeckRoute?
    public var match: DeckWindowMatch?

    public init(
        name: String? = nil,
        type: DeckActionType? = nil,
        run: String? = nil,
        app: String? = nil,
        bundleId: String? = nil,
        urls: [String] = [],
        paths: [String] = [],
        cwd: String? = nil,
        command: String? = nil,
        profile: String? = nil,
        newWindow: Bool = true,
        wait: Bool = true,
        route: DeckRoute? = nil,
        match: DeckWindowMatch? = nil,
    ) {
        self.name = name
        self.type = type
        self.run = run
        self.app = app
        self.bundleId = bundleId
        self.urls = urls
        self.paths = paths
        self.cwd = cwd
        self.command = command
        self.profile = profile
        self.newWindow = newWindow
        self.wait = wait
        self.route = route
        self.match = match
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case run
        case app
        case bundleId = "bundle-id"
        case urls
        case paths
        case path
        case cwd
        case command
        case profile
        case newWindow = "new-window"
        case wait
        case route
        case match
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(DeckActionType.self, forKey: .type)
        run = try container.decodeIfPresent(String.self, forKey: .run)
        app = try container.decodeIfPresent(String.self, forKey: .app)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        var decodedPaths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
        if let path = try container.decodeIfPresent(String.self, forKey: .path) {
            decodedPaths.append(path)
        }
        paths = decodedPaths
        urls = try container.decodeIfPresent([String].self, forKey: .urls) ?? []
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        newWindow = try container.decodeIfPresent(Bool.self, forKey: .newWindow) ?? true
        wait = try container.decodeIfPresent(Bool.self, forKey: .wait) ?? true
        route = try container.decodeIfPresent(DeckRoute.self, forKey: .route)
        match = try container.decodeIfPresent(DeckWindowMatch.self, forKey: .match)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(run, forKey: .run)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
        if !urls.isEmpty { try container.encode(urls, forKey: .urls) }
        if !paths.isEmpty { try container.encode(paths, forKey: .paths) }
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(profile, forKey: .profile)
        if newWindow != true { try container.encode(newWindow, forKey: .newWindow) }
        if wait != true { try container.encode(wait, forKey: .wait) }
        try container.encodeIfPresent(route, forKey: .route)
        try container.encodeIfPresent(match, forKey: .match)
    }
}

public enum DeckActionType: String, Codable, Equatable, Sendable {
    case shell
    case app
    case url
    case file
    case browser
    case terminal
    case bunch
}

public struct DeckRoute: Codable, Equatable, Sendable {
    public var workspace: String?
    public var tabGroup: String?
    public var focus: Bool
    public var reuseExisting: Bool
    public var timeoutSeconds: Double

    public init(
        workspace: String? = nil,
        tabGroup: String? = nil,
        focus: Bool = false,
        reuseExisting: Bool = false,
        timeoutSeconds: Double = 10,
    ) {
        self.workspace = workspace
        self.tabGroup = tabGroup
        self.focus = focus
        self.reuseExisting = reuseExisting
        self.timeoutSeconds = timeoutSeconds
    }

    enum CodingKeys: String, CodingKey {
        case workspace
        case tabGroup = "tab-group"
        case focus
        case reuseExisting = "reuse-existing"
        case timeoutSeconds = "timeout-seconds"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        tabGroup = try container.decodeIfPresent(String.self, forKey: .tabGroup)
        focus = try container.decodeIfPresent(Bool.self, forKey: .focus) ?? false
        reuseExisting = try container.decodeIfPresent(Bool.self, forKey: .reuseExisting) ?? false
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) {
            timeoutSeconds = doubleValue
        } else if let intValue = try? container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) {
            timeoutSeconds = Double(intValue)
        } else {
            timeoutSeconds = 10
        }
    }
}

public struct DeckWindowMatch: Codable, Equatable, Sendable {
    public var bundleId: String?
    public var appName: String?
    public var titleContains: String?
    public var titleEquals: String?

    public init(
        bundleId: String? = nil,
        appName: String? = nil,
        titleContains: String? = nil,
        titleEquals: String? = nil,
    ) {
        self.bundleId = bundleId
        self.appName = appName
        self.titleContains = titleContains
        self.titleEquals = titleEquals
    }

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle-id"
        case appName = "app-name"
        case titleContains = "title-contains"
        case titleEquals = "title-equals"
    }

    public var isEmpty: Bool {
        bundleId == nil && appName == nil && titleContains == nil && titleEquals == nil
    }
}
