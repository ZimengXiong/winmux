@testable import AppBundle
import AppKit
import Common
import XCTest

extension ConfigTest {
    func testParseWorkspaceSidebar() {
        let (parsed, errors) = parseConfig(
            """
            [workspace-sidebar]
                enabled = true
                width = 280
                monitor = ['secondary', 2]
                show-status-pills = false
                show-date = false
                menu-bar-reserve-height = 30
                project-deletion-action = 'move-windows-to-fallback'

            [workspace-sidebar.workspace-labels]
                1 = 'Code'
                2 = 'Web'

            [workspace-sidebar.project-labels]
                default = 'Personal'

            [workspace-sidebar.project-colors]
                default = '#ff8844'
            """,
        )
        assertEquals(errors, [])
        assertEquals(
            parsed.workspaceSidebar,
            WorkspaceSidebarConfig(
                enabled: true,
                collapsedWidth: 44,
                width: 280,
                monitor: [.secondary, .sequenceNumber(2)],
                showStatusPills: false,
                showDate: false,
                menuBarReserveHeight: 30,
                projectDeletionAction: .moveWindowsToFallback,
                workspaceLabels: ["1": "Code", "2": "Web"],
                projectLabels: ["default": "Personal"],
                projectColors: ["default": "#FF8844"],
            ),
        )

        let (_, widthErrors) = parseConfig(
            """
            [workspace-sidebar]
                collapsed-width = 0
                width = 0
                menu-bar-reserve-height = -1
            """,
        )
        assertEquals(widthErrors.descriptions, [
            "workspace-sidebar.collapsed-width: Must be greater than 0",
            "workspace-sidebar.menu-bar-reserve-height: Must be greater than or equal to 0",
            "workspace-sidebar.width: Must be greater than 0",
        ])

        let (_, colorErrors) = parseConfig(
            """
            [workspace-sidebar.project-colors]
                default = 'not-a-color'
            """,
        )
        assertEquals(colorErrors.descriptions, [
            "workspace-sidebar.project-colors.default: Must be a hex color like '#RRGGBB'",
        ])

        let (_, actionErrors) = parseConfig(
            """
            [workspace-sidebar]
                project-deletion-action = 'explode'
            """,
        )
        assertEquals(actionErrors.descriptions, [
            "workspace-sidebar.project-deletion-action: Possible values: close-windows, move-windows-to-fallback",
        ])
    }

    func testParseWindowTabs() {
        let (parsed, errors) = parseConfig(
            """
            [window-tabs]
                enabled = true
                height = 38
            """,
        )
        assertEquals(errors, [])
        assertEquals(parsed.windowTabs, WindowTabsConfig(enabled: true, height: 38))

        let (_, heightErrors) = parseConfig(
            """
            [window-tabs]
                height = 20
            """,
        )
        assertEquals(heightErrors.descriptions, [
            "window-tabs.height: Must be greater than 20",
        ])
    }

    func testParseEnableWindowManagement() {
        let (parsed, errors) = parseConfig(
            """
            enable-window-management = false
            """,
        )
        assertEquals(errors, [])
        XCTAssertFalse(parsed.enableWindowManagement)
    }

    func testParseRectangleShortcutsPresetSeedsMainMode() {
        let (parsed, errors) = parseConfig(
            """
            shortcuts-preset = 'rectangle'
            [mode.foo.binding]
                alt-h = 'focus left'
            """,
        )
        assertEquals(errors, [])
        XCTAssertEqual(parsed.shortcutsPreset, .rectangle)
        XCTAssertNotNil(parsed.modes[mainModeId])
        XCTAssertNotNil(parsed.modes["foo"])

        let leftBinding = HotkeyBinding(.control.union(.option), .leftArrow, [
            SnapCommand(args: SnapCmdArgs(rawArgs: [], action: .leftHalf)),
        ])
        let maximizeBinding = HotkeyBinding(.control.union(.option), .return, [
            SnapCommand(args: SnapCmdArgs(rawArgs: [], action: .maximize)),
        ])
        assertEquals(parsed.modes[mainModeId]?.bindings[leftBinding.descriptionWithKeyCode], leftBinding)
        assertEquals(parsed.modes[mainModeId]?.bindings[maximizeBinding.descriptionWithKeyCode], maximizeBinding)
    }

    func testRectangleShortcutsPresetDoesNotOverrideExplicitBindings() {
        let (parsed, errors) = parseConfig(
            """
            shortcuts-preset = 'rectangle'
            [mode.main.binding]
                ctrl-alt-left = 'focus left'
            """,
        )
        assertEquals(errors, [])

        let explicitBinding = HotkeyBinding(.control.union(.option), .leftArrow, [FocusCommand.new(direction: .left)])
        let seededBinding = HotkeyBinding(.control.union(.option), .rightArrow, [
            SnapCommand(args: SnapCmdArgs(rawArgs: [], action: .rightHalf)),
        ])
        assertEquals(parsed.modes[mainModeId]?.bindings[explicitBinding.descriptionWithKeyCode], explicitBinding)
        assertEquals(parsed.modes[mainModeId]?.bindings[seededBinding.descriptionWithKeyCode], seededBinding)
    }

    func testParseOnWindowDetected() {
        let (parsed, errors) = parseConfig(
            """
            [[on-window-detected]] # 0
                check-further-callbacks = true
                run = ['layout floating', 'move-node-to-workspace W']
            [[on-window-detected]] # 1
                if.app-id = 'com.apple.systempreferences'
                run = []
            [[on-window-detected]] # 2
            [[on-window-detected]] # 3
                run = ['move-node-to-workspace S', 'layout tiling']
            [[on-window-detected]] # 4
                run = ['move-node-to-workspace S', 'move-node-to-workspace W']
            [[on-window-detected]] # 5
                run = ['move-node-to-workspace S', 'layout h_tiles']
            """,
        )
        assertEquals(parsed.onWindowDetected, [
            WindowDetectedCallback( // 0
                matcher: WindowDetectedCallbackMatcher(
                    appId: nil,
                    appNameRegexSubstring: nil,
                    windowTitleRegexSubstring: nil,
                ),
                checkFurtherCallbacks: true,
                rawRun: [
                    LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.floating])),
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W")),
                ],
            ),
            WindowDetectedCallback( // 1
                matcher: WindowDetectedCallbackMatcher(
                    appId: "com.apple.systempreferences",
                    appNameRegexSubstring: nil,
                    windowTitleRegexSubstring: nil,
                ),
                rawRun: [],
            ),
            WindowDetectedCallback( // 3
                rawRun: [
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S")),
                    LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiling])),
                ],
            ),
            WindowDetectedCallback( // 4
                rawRun: [
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S")),
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W")),
                ],
            ),
            WindowDetectedCallback( // 5
                rawRun: [
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S")),
                    LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.h_tiles])),
                ],
            ),
        ])

        assertEquals(errors.descriptions, [
            "on-window-detected[2]: \'run\' is mandatory key",
        ])
    }

    func testParseOnWindowDetectedRegex() {
        let (config, errors) = parseConfig(
            """
            [[on-window-detected]]
                if.app-name-regex-substring = '^system settings$'
                run = []
            """,
        )
        XCTAssertTrue(config.onWindowDetected.singleOrNil()!.matcher.appNameRegexSubstring != nil)
        assertEquals(errors, [])
    }

    func testRegex() {
        var devNull: [String] = []
        XCTAssertTrue("System Settings".contains(parseCaseInsensitiveRegex("settings").getOrNil(appendErrorTo: &devNull)!))
        XCTAssertTrue(!"System Settings".contains(parseCaseInsensitiveRegex("^settings^").getOrNil(appendErrorTo: &devNull)!))
    }

    func testParseGaps() {
        let (config, errors1) = parseConfig(
            """
            [gaps]
                inner.horizontal = 10
                inner.vertical = [{ monitor."main" = 1 }, { monitor."secondary" = 2 }, 5]
                outer.left = 12
                outer.bottom = 13
                outer.top = [{ monitor."built-in" = 3 }, { monitor."secondary" = 4 }, 6]
                outer.right = [{ monitor.2 = 7 }, 8]
            """,
        )
        assertEquals(errors1, [])
        assertEquals(
            config.gaps,
            Gaps(
                inner: .init(
                    vertical: .perMonitor(
                        [PerMonitorValue(description: .main, value: 1), PerMonitorValue(description: .secondary, value: 2)],
                        default: 5,
                    ),
                    horizontal: .constant(10),
                ),
                outer: .init(
                    left: .constant(12),
                    bottom: .constant(13),
                    top: .perMonitor(
                        [
                            PerMonitorValue(description: .caseSensitivePattern("built-in")!, value: 3),
                            PerMonitorValue(description: .secondary, value: 4),
                        ],
                        default: 6,
                    ),
                    right: .perMonitor([PerMonitorValue(description: .sequenceNumber(2), value: 7)], default: 8),
                ),
            ),
        )

        let (_, errors2) = parseConfig(
            """
            [gaps]
                inner.horizontal = [true]
                inner.vertical = [{ foo.main = 1 }, { monitor = { foo = 2, bar = 3 } }, 1]
            """,
        )
        assertEquals(errors2.descriptions, [
            "gaps.inner.horizontal: The last item in the array must be of type Int",
            "gaps.inner.vertical[0]: The table is expected to have a single key \'monitor\'",
            "gaps.inner.vertical[1].monitor: The table is expected to have a single key",
        ])
    }

    func testParseKeyMapping() {
        let (config, errors) = parseConfig(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'q'
                unicorn = 'u'

            [mode.main.binding]
                alt-unicorn = 'workspace wonderland'
            """,
        )
        assertEquals(errors.descriptions, [])
        assertEquals(config.keyMapping, KeyMapping(preset: .qwerty, rawKeyNotationToKeyCode: [
            "q": .q,
            "unicorn": .u,
        ]))
        let binding = HotkeyBinding(.option, .u, [WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("unicorn").getOrDie())))])
        assertEquals(config.modes[mainModeId]?.bindings, [binding.descriptionWithKeyCode: binding])

        let (_, errors1) = parseConfig(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'qw'
                ' f' = 'f'
            """,
        )
        assertEquals(errors1.descriptions, [
            "key-mapping.key-notation-to-key-code: ' f' is invalid key notation",
            "key-mapping.key-notation-to-key-code.q: 'qw' is invalid key code",
        ])

        let (dvorakConfig, dvorakErrors) = parseConfig(
            """
            key-mapping.preset = 'dvorak'
            """,
        )
        assertEquals(dvorakErrors, [])
        assertEquals(dvorakConfig.keyMapping, KeyMapping(preset: .dvorak, rawKeyNotationToKeyCode: [:]))
        assertEquals(dvorakConfig.keyMapping.resolve()["quote"], .q)
        let (colemakConfig, colemakErrors) = parseConfig(
            """
            key-mapping.preset = 'colemak'
            """,
        )
        assertEquals(colemakErrors, [])
        assertEquals(colemakConfig.keyMapping, KeyMapping(preset: .colemak, rawKeyNotationToKeyCode: [:]))
        assertEquals(colemakConfig.keyMapping.resolve()["f"], .e)
    }

}
