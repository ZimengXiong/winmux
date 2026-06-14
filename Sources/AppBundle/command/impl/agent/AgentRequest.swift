import AppKit
import Common
import Foundation

// MARK: - Input

struct AgentRequest: Decodable {
    let schemaVersion: Int?
    let snapshotId: String?
    let worldId: String?
    let edit: AgentEdit?

    static func read(path: String) throws -> AgentRequest {
        let data = try Data(contentsOf: URL(filePath: path))
        return try JSONDecoder().decode(AgentRequest.self, from: data)
    }

    var operations: [AgentOperation] {
        (edit?.operations ?? []) + (edit?.actions ?? [])
    }

    @MainActor
    func validate() async throws -> [String] {
        var errors: [String] = []
        validateFreshWorldId(appendTo: &errors)
        guard errors.isEmpty else { return errors }
        var context = AgentValidationContext()
        for operation in operations {
            try await operation.validate(context: &context, appendTo: &errors)
        }
        if let layout = edit?.layout {
            try await layout.validate(appendTo: &errors)
        }
        return errors
    }

    @MainActor
    func validateFreshWorldId(appendTo errors: inout [String]) {
        if let worldId {
            let currentWorldId = currentAgentWorldId()
            if worldId != currentWorldId {
                errors.append("Agent JSON is stale: worldId '\(worldId)' does not match current worldId '\(currentWorldId)'. Run 'winmux agent query --path <path>' again before applying.")
            }
        } else if snapshotId != nil {
            errors.append("Agent JSON is missing worldId. Run 'winmux agent query --path <path>' again before applying.")
        }
    }

    @MainActor
    func apply() async throws {
        var context = AgentApplyContext()
        for operation in operations {
            try await operation.apply(context: &context)
        }
        if let layout = edit?.layout {
            try await layout.apply()
        }
    }
}

struct AgentEdit: Decodable {
    let mode: String?
    let operations: [AgentOperation]?
    let actions: [AgentOperation]?
    let layout: AgentLayoutEdit?
}

struct AgentValidationContext {
    var plannedTabGroups: [String: Set<UInt32>] = [:]
}

struct AgentApplyContext {
    var tabGroupAliases: [String: TilingContainer] = [:]
}

struct AgentLayoutEdit: Codable {
    let workspaces: [AgentWorkspaceLayout]

    @MainActor
    func validate(appendTo errors: inout [String]) async throws {
        for workspace in workspaces {
            try await workspace.validate(appendTo: &errors)
        }
    }

    @MainActor
    func apply() async throws {
        for workspace in workspaces {
            try await workspace.apply()
        }
    }
}

