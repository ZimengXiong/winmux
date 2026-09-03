@testable import AppBundle
import Common
import Foundation
import XCTest

@MainActor
final class ProjectLifecycleCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParsesProjectLifecycleSurface() {
        XCTAssertNotNil(parseCommand("create-project --name 'Research Lab' --color '#60a5fa' --json").cmdOrNil)
        XCTAssertNotNil(parseCommand("list-projects --focused no --visible --json").cmdOrNil)
        XCTAssertNotNil(parseCommand("rename-project project-1 'Research Lab' --fail-if-noop --json").cmdOrNil)
        XCTAssertNotNil(parseCommand("set-project-color project-1 auto --json").cmdOrNil)
        XCTAssertNotNil(parseCommand("delete-project project-1 --action move-windows-to-fallback --if-window-count 0").cmdOrNil)

        XCTAssertEqual(
            parseCommand("delete-project project-1").errorOrNil,
            "Mandatory option is not specified (--action)",
        )
        XCTAssertEqual(
            parseCommand("delete-project project-1 --action move-windows-to-fallback").errorOrNil,
            "Mandatory option is not specified (--if-window-count)",
        )
        XCTAssertEqual(
            parseCommand("delete-project project-1 --action close-windows --if-window-count 0").errorOrNil,
            "ERROR: Can't parse 'close-windows'. Possible values: (move-windows-to-fallback)",
        )
        XCTAssertEqual(
            parseCommand("list-projects --count --json").errorOrNil,
            "ERROR: Conflicting options: --count, --json",
        )
        XCTAssertFalse(CreateProjectCmdArgs.info.allowInConfig)
        XCTAssertFalse(RenameProjectCmdArgs.info.allowInConfig)
        XCTAssertFalse(SetProjectColorCmdArgs.info.allowInConfig)
        XCTAssertFalse(DeleteProjectCmdArgs.info.allowInConfig)
    }

    func testCreateValidatesBeforeMutatingAndReturnsStableId() async throws {
        let invalidResult = try await run("create-project --color tomato")
        XCTAssertEqual(invalidResult.exitCode, 1)
        XCTAssertEqual(workspaceProjects().map(\.id), [workspaceProjectDefaultId])

        let result = try await run("create-project --name 'Research Lab' --color 60a5fa --json")
        XCTAssertEqual(result.exitCode, 0)
        let json = try jsonObject(result)
        let projectId = try XCTUnwrap(json["project-id"] as? String)
        assertUuidProjectId(projectId)
        XCTAssertEqual(json["project-name"] as? String, "Research Lab")
        XCTAssertEqual(json["project-color"] as? String, "#60A5FA")
        XCTAssertEqual(config.workspaceSidebar.projectLabels[projectId], "Research Lab")
        XCTAssertEqual(config.workspaceSidebar.projectColors[projectId], "#60A5FA")
        XCTAssertEqual(orderedWorkspaces(in: WorkspaceProjectId(projectId)).count, 1)

        let plainResult = try await run("create-project")
        XCTAssertEqual(plainResult.exitCode, 0)
        let secondProjectId = try XCTUnwrap(plainResult.stdout.singleOrNil())
        assertUuidProjectId(secondProjectId)
        XCTAssertNotEqual(secondProjectId, projectId)
    }

    func testListProjectsSupportsPlainJsonFiltersAndCounts() async throws {
        let projectId = try await createProject("--name Work --color '#123abc'")

        let plainResult = try await run("list-projects")
        XCTAssertEqual(plainResult.exitCode, 0)
        XCTAssertEqual(plainResult.stdout.count, 2)
        XCTAssertTrue(plainResult.stdout[0].contains("default"))
        XCTAssertTrue(plainResult.stdout[1].contains(projectId.rawValue))
        XCTAssertTrue(plainResult.stdout[1].contains("Work"))

        let jsonResult = try await run("list-projects --json")
        let rows = try jsonArray(jsonResult)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["project-index"] as? Int, 1)
        XCTAssertEqual(rows[0]["project-id"] as? String, "default")
        XCTAssertEqual(rows[0]["project-is-focused"] as? Bool, true)
        XCTAssertEqual(rows[1]["project-id"] as? String, projectId.rawValue)
        XCTAssertEqual(rows[1]["project-name"] as? String, "Work")
        XCTAssertEqual(rows[1]["project-color"] as? String, "#123ABC")
        XCTAssertEqual(rows[1]["project-workspace-count"] as? Int, 1)
        XCTAssertEqual(rows[1]["project-window-count"] as? Int, 0)

        let countResult = try await run("list-projects --focused no --count")
        XCTAssertEqual(countResult.stdout, ["1"])
        let customResult = try await run("list-projects --format '%{project-id}:%{project-name}' --visible no")
        XCTAssertEqual(customResult.stdout, ["\(projectId.rawValue):Work"])
    }

    func testRenameAndColorUseStableIdAndReportNoops() async throws {
        let projectId = try await createProject()

        let renameResult = try await run("rename-project \(projectId.rawValue) 'Client One' --json")
        XCTAssertEqual(renameResult.exitCode, 0)
        XCTAssertEqual(try jsonObject(renameResult)["changed"] as? Bool, true)
        XCTAssertEqual(workspaceProject(id: projectId.rawValue)?.name, "Client One")

        let renameNoop = try await run("rename-project \(projectId.rawValue) 'Client One' --fail-if-noop")
        XCTAssertEqual(renameNoop.exitCode, 1)
        XCTAssertEqual(renameNoop.stderr, ["Project '\(projectId.rawValue)' is already named 'Client One'"])

        let colorResult = try await run("set-project-color \(projectId.rawValue) aabbcc --json")
        XCTAssertEqual(colorResult.exitCode, 0)
        XCTAssertEqual(try jsonObject(colorResult)["project-color"] as? String, "#AABBCC")
        XCTAssertEqual(config.workspaceSidebar.projectColors[projectId.rawValue], "#AABBCC")

        let resetResult = try await run("set-project-color \(projectId.rawValue) auto --json")
        XCTAssertEqual(resetResult.exitCode, 0)
        XCTAssertEqual(try jsonObject(resetResult)["project-color"] as? String, "auto")
        XCTAssertNil(config.workspaceSidebar.projectColors[projectId.rawValue])

        let invalidResult = try await run("set-project-color \(projectId.rawValue) '#12345'")
        XCTAssertEqual(invalidResult.exitCode, 1)
        XCTAssertTrue(invalidResult.stderr.singleOrNil()?.contains("Invalid project color") == true)
    }

    func testCreateAndRenameRejectEveryControlCharacterBeforeMutation() async throws {
        let projectId = try await createProject("--name Original")
        let originalProjectCount = workspaceProjects().count
        let controlScalars = (Array(0x00 ... 0x1F) + Array(0x7F ... 0x9F))
            .compactMap(UnicodeScalar.init)

        for scalar in controlScalars {
            let invalidName = "Invalid\(String(scalar))Name"
            XCTAssertThrowsError(try createWorkspaceProjectForCommand(displayName: invalidName, colorHex: nil))
            XCTAssertThrowsError(try renameWorkspaceProject(projectId, displayName: invalidName))
        }

        XCTAssertEqual(workspaceProjects().count, originalProjectCount)
        XCTAssertEqual(workspaceProject(id: projectId.rawValue)?.name, "Original")
        XCTAssertEqual(config.workspaceSidebar.projectLabels[projectId.rawValue], "Original")
    }

    func testStableIdTargetsFocusAndMoveCommands() async throws {
        let projectId = try await createProject("--name Work")

        let focusResult = try await run("project \(projectId.rawValue)")
        XCTAssertEqual(focusResult.exitCode, 0)
        XCTAssertEqual(focus.workspace.projectId, projectId)

        let defaultWorkspace = orderedWorkspaces(in: workspaceProjectDefaultId).first.orDie()
        let window = TestWindow.new(id: 701, parent: defaultWorkspace.rootTilingContainer)
        _ = window.focusWindow()
        let moveResult = try await run("move-node-to-project \(projectId.rawValue)")
        XCTAssertEqual(moveResult.exitCode, 0)
        XCTAssertEqual(window.nodeWorkspace?.projectId, projectId)

        let missingResult = try await run("project project-missing")
        XCTAssertEqual(missingResult.exitCode, 1)
        XCTAssertEqual(missingResult.stderr, ["Project 'project-missing' doesn't exist"])
    }

    func testExplicitProjectIdDisambiguatesReservedAndNumericIds() {
        let reserved = parseCommand("project --project-id next").cmdOrNil as? ProjectCommand
        XCTAssertEqual(reserved?.args.target, .initialized(.directId("next")))
        let numeric = parseCommand("move-node-to-project --project-id 2").cmdOrNil as? MoveNodeToProjectCommand
        XCTAssertEqual(numeric?.args.target, .initialized(.directId("2")))
        let dashPrefixed = parseCommand("project --project-id -imported").cmdOrNil as? ProjectCommand
        XCTAssertEqual(dashPrefixed?.args.target, .initialized(.directId("-imported")))

        XCTAssertEqual(
            parseCommand("project next --project-id next").errorOrNil,
            "--project-id is incompatible with a positional project target",
        )
    }

    func testDeleteRequiresExplicitActionAndNeverReadsConfigDefault() async throws {
        let fallbackWorkspace = orderedWorkspaces(in: workspaceProjectDefaultId).first.orDie()
        _ = TestWindow.new(id: 710, parent: fallbackWorkspace.rootTilingContainer)
        let projectId = try await createProject("--name Disposable")
        let projectWorkspace = orderedWorkspaces(in: projectId).first.orDie()
        let movedWindow = TestWindow.new(id: 711, parent: projectWorkspace.rootTilingContainer)
        config.workspaceSidebar.projectDeletionAction = .closeWindows

        let staleResult = try await run(
            "delete-project \(projectId.rawValue) --action move-windows-to-fallback --if-window-count 0",
        )
        XCTAssertEqual(staleResult.exitCode, 1)
        XCTAssertEqual(movedWindow.nodeWorkspace?.projectId, projectId)
        XCTAssertNotNil(workspaceProject(id: projectId.rawValue))

        let moveResult = try await run(
            "delete-project \(projectId.rawValue) --action move-windows-to-fallback --if-window-count 1 --json",
        )
        XCTAssertEqual(moveResult.exitCode, 0)
        let json = try jsonObject(moveResult)
        XCTAssertEqual(json["deleted-project-id"] as? String, projectId.rawValue)
        XCTAssertEqual(json["fallback-project-id"] as? String, "default")
        XCTAssertEqual(json["window-action"] as? String, "move-windows-to-fallback")
        XCTAssertEqual(json["window-count"] as? Int, 1)
        XCTAssertEqual(movedWindow.nodeWorkspace?.projectId, workspaceProjectDefaultId)
        XCTAssertNil(workspaceProject(id: projectId.rawValue))

        let defaultResult = try await run("delete-project default --action move-windows-to-fallback --if-window-count 1")
        XCTAssertEqual(defaultResult.exitCode, 1)
        XCTAssertTrue(defaultResult.stderr.singleOrNil()?.contains("cannot be deleted") == true)
    }

    private func run(_ command: String) async throws -> CmdResult {
        try await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
    }

    private func createProject(_ options: String = "") async throws -> WorkspaceProjectId {
        let result = try await run("create-project \(options)")
        XCTAssertEqual(result.exitCode, 0)
        let rawId = try XCTUnwrap(result.stdout.singleOrNil())
        assertUuidProjectId(rawId)
        return WorkspaceProjectId(rawId)
    }

    private func assertUuidProjectId(_ rawId: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(rawId.hasPrefix("project-"), file: file, line: line)
        XCTAssertNotNil(UUID(uuidString: String(rawId.dropFirst("project-".count))), file: file, line: line)
    }

    private func jsonObject(_ result: CmdResult) throws -> [String: Any] {
        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.singleOrNil()?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func jsonArray(_ result: CmdResult) throws -> [[String: Any]] {
        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.singleOrNil()?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
}
