@testable import AppBundle
import Foundation
import XCTest

extension AgentCommandTest {
    func testCreateTabGroupAliasCanBeUsedLaterInSameOperations() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  {
                    "type": "createTabGroup",
                    "tabGroupId": "tabgroup-chrome",
                    "tabs": [1, 2],
                    "activeWindowId": 1
                  },
                  {
                    "type": "placePane",
                    "pane": { "tabGroupId": "tabgroup-chrome" },
                    "relation": "rightOf",
                    "target": { "windowId": 3 }
                  },
                  {
                    "type": "setPaneSize",
                    "pane": { "tabGroupId": "tabgroup-chrome" },
                    "size": 0.8
                  }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        let group = try XCTUnwrap(root.allAgentTabGroupsForTests.singleOrNil())
        XCTAssertEqual(group.agentWindowIdsForTests, [1, 2])
        XCTAssertTrue(root.children.last === group)
        XCTAssertEqual(group.getWeight(.h) / root.getWeight(.h), 0.8, accuracy: 0.0001)
    }

    func testDeclarativeWorkspaceLayout() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "layout": {
                  "workspaces": [
                    {
                      "name": "coding",
                      "layout": {
                        "kind": "split",
                        "direction": "horizontal",
                        "children": [
                          { "kind": "window", "windowId": 1 },
                          { "kind": "tabGroup", "tabs": [2, 3], "activeWindowId": 3 }
                        ]
                      },
                      "focus": { "windowId": 3 }
                    }
                  ]
                }
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        let targetRoot = Workspace.get(byName: "coding").rootTilingContainer
        XCTAssertEqual((targetRoot.children.first as? Window)?.windowId, 1)
        let group = targetRoot.children.last as? TilingContainer
        XCTAssertEqual(group?.layout, .tabGroup)
        XCTAssertEqual(group?.agentWindowIdsForTests, [2, 3])
        XCTAssertEqual(group?.tabActiveWindow?.windowId, 3)
        XCTAssertEqual(focus.windowOrNil?.windowId, 3)
    }

    func testDeclarativeWorkspaceLayoutUsesProportionalSizes() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "layout": {
                  "workspaces": [
                    {
                      "name": "coding",
                      "layout": {
                        "kind": "split",
                        "direction": "horizontal",
                        "children": [
                          { "kind": "window", "windowId": 1, "size": 0.8 },
                          {
                            "kind": "split",
                            "direction": "vertical",
                            "size": 0.2,
                            "children": [
                              { "kind": "window", "windowId": 2, "sizePercent": 75 },
                              { "kind": "window", "windowId": 3, "size": 0.25 }
                            ]
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        let targetRoot = Workspace.get(byName: "coding").rootTilingContainer
        let left = targetRoot.children[0]
        let rightSplit = try XCTUnwrap(targetRoot.children[1] as? TilingContainer)
        XCTAssertEqual(left.getWeight(.h) / targetRoot.getWeight(.h), 0.8, accuracy: 0.0001)
        XCTAssertEqual(rightSplit.getWeight(.h) / targetRoot.getWeight(.h), 0.2, accuracy: 0.0001)
        XCTAssertEqual(rightSplit.children[0].getWeight(.v) / rightSplit.getWeight(.v), 0.75, accuracy: 0.0001)
        XCTAssertEqual(rightSplit.children[1].getWeight(.v) / rightSplit.getWeight(.v), 0.25, accuracy: 0.0001)
    }

    func testDeclarativeWorkspaceLayoutRejectsDuplicateWindows() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "layout": {
                  "workspaces": [
                    {
                      "name": "coding",
                      "layout": {
                        "kind": "split",
                        "direction": "horizontal",
                        "children": [
                          { "kind": "window", "windowId": 1 },
                          { "kind": "tabGroup", "tabs": [1, 2] }
                        ]
                      }
                    }
                  ]
                }
              }
            }
            """)

        let result = try await parseCommand("agent check --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.joined(separator: "\n").contains("setWorkspaceLayout 'coding': window 1 appears more than once"))
    }

    func testSetPaneSizeOperationUsesProportionalSize() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "setPaneSize", "pane": { "windowId": 1 }, "size": 80 }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(root.children[0].getWeight(.h) / root.getWeight(.h), 0.8, accuracy: 0.0001)
        XCTAssertEqual(root.children[1].getWeight(.h) / root.getWeight(.h), 0.2, accuracy: 0.0001)
    }

    func testSetPaneSizeOperationCanTargetVerticalSplit() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        let rightSplit = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tiles, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 2, parent: rightSplit)
        _ = TestWindow.new(id: 3, parent: rightSplit)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "operations": [
                  { "type": "setPaneSize", "pane": { "windowId": 2 }, "axis": "vertical", "size": 0.75 },
                  { "type": "setPaneSize", "pane": { "windowId": 2 }, "axis": "horizontal", "size": 0.2 }
                ]
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(rightSplit.children[0].getWeight(.v) / rightSplit.getWeight(.v), 0.75, accuracy: 0.0001)
        XCTAssertEqual(rightSplit.children[1].getWeight(.v) / rightSplit.getWeight(.v), 0.25, accuracy: 0.0001)
        XCTAssertEqual(rightSplit.getWeight(.h) / root.getWeight(.h), 0.2, accuracy: 0.0001)
        XCTAssertEqual(root.children[0].getWeight(.h) / root.getWeight(.h), 0.8, accuracy: 0.0001)
    }

    func testDeclarativeSingleWindowLayoutStaysTiled() async throws {
        let root = Workspace.get(byName: "a").rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)

        let path = try writeAgentJson("""
            {
              "schemaVersion": 1,
              "edit": {
                "layout": {
                  "workspaces": [
                    {
                      "name": "coding",
                      "layout": { "kind": "window", "windowId": 1 }
                    }
                  ]
                }
              }
            }
            """)

        let result = try await parseCommand("agent apply --path \(path.path)").cmdOrDie.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        let targetRoot = Workspace.get(byName: "coding").rootTilingContainer
        XCTAssertEqual((targetRoot.children.first as? Window)?.windowId, 1)
        XCTAssertFalse((targetRoot.children.first as? Window)?.isFloating ?? true)
    }
}
