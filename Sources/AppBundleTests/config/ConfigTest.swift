@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ConfigTest: XCTestCase {
    func testParseI3Config() {
        let toml =
            """
            config-version = 2
            persistent-workspaces = []
            enable-normalization-flatten-containers = false
            enable-normalization-opposite-orientation-for-nested-containers = false
            on-focused-monitor-changed = ['move-mouse monitor-lazy-center']

            [mode.main.binding]
                alt-enter = '''exec-and-forget osascript -e '
                tell application "Terminal"
                    do script
                    activate
                end tell'
                '''
                alt-j = 'focus --boundaries-action wrap-around-the-workspace left'
                alt-k = 'focus --boundaries-action wrap-around-the-workspace down'
                alt-l = 'focus --boundaries-action wrap-around-the-workspace up'
                alt-semicolon = 'focus --boundaries-action wrap-around-the-workspace right'
            """
        let (i3Config, errors) = parseConfig(toml)
        assertEquals(errors, [])
        assertEquals(i3Config.execConfig, defaultConfig.execConfig)
        assertEquals(i3Config.enableNormalizationFlattenContainers, false)
        assertEquals(i3Config.enableNormalizationOppositeOrientationForNestedContainers, false)
    }

    func testParseDefaultConfig() throws {
        let toml = try String(contentsOf: projectRoot.appending(component: "resources/default-config.toml"), encoding: .utf8)
        let (_, errors) = parseConfig(toml)
        assertEquals(errors, [])
    }

    func testConfigVersionOutOfBounds() {
        let (_, errors) = parseConfig(
            """
            config-version = 0
            """,
        )
        assertEquals(errors.descriptions, ["config-version: Must be in [1, 2] range"])
    }

    func testExecOnWorkspaceChangeDifferentTypesError() {
        let (_, errors) = parseConfig(
            """
            exec-on-workspace-change = ['', 1]
            """,
        )
        assertEquals(errors.descriptions, ["exec-on-workspace-change[1]: Expected type is \'string\'. But actual type is \'integer\'"])
    }

    func testDuplicatedPersistentWorkspaces() {
        let (_, errors) = parseConfig(
            """
            config-version = 2
            persistent-workspaces = ['a', 'a']
            """,
        )
        assertEquals(errors.descriptions, ["persistent-workspaces: Contains duplicated workspace names"])
    }

    func testPersistentWorkspacesAreAvailableOnlySinceVersion2() {
        let (_, errors) = parseConfig(
            """
            persistent-workspaces = ['a']
            """,
        )
        assertEquals(errors.descriptions, ["persistent-workspaces: This config option is only available since \'config-version = 2\'"])
    }

    func testQueryCantBeUsedInConfig() {
        let (_, errors) = parseConfig(
            """
            [mode.main.binding]
                alt-a = 'list-apps'
            """,
        )
        XCTAssertTrue(errors.descriptions.singleOrNil()?.contains("cannot be used in config") == true)
    }

    func testDropBindings() {
        let (config, errors) = parseConfig(
            """
            mode.main = {}
            """,
        )
        assertEquals(errors, [])
        XCTAssertTrue(config.modes[mainModeId]?.bindings.isEmpty == true)
    }

    func testParseMode() {
        let (config, errors) = parseConfig(
            """
            [mode.main.binding]
                alt-h = 'focus left'
            """,
        )
        assertEquals(errors, [])
        let binding = HotkeyBinding(.option, .h, [FocusCommand.new(direction: .left)])
        assertEquals(
            config.modes[mainModeId],
            Mode(bindings: [binding.descriptionWithKeyCode: binding], tapBindings: [:]),
        )
    }

    func testParseTapBindings() {
        let (config, errors) = parseConfig(
            """
            [mode.main.binding-tap]
                left-alt = 'focus left'
                right-cmd = 'workspace 2'
            """,
        )
        assertEquals(errors, [])
        assertEquals(
            config.modes[mainModeId],
            Mode(
                bindings: [:],
                tapBindings: [
                    "left-alt": TapBinding(.leftAlt, [FocusCommand.new(direction: .left)]),
                    "right-cmd": TapBinding(.rightCmd, [WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())))]),
                ],
            ),
        )
    }

    func testTapModifierStateClearsAfterMissedRelease() async throws {
        resetHotKeys()
        config.modes = [
            mainModeId: Mode(
                bindings: [:],
                tapBindings: [
                    "left-alt": TapBinding(.leftAlt, [FocusCommand.new(direction: .left)]),
                    "right-cmd": TapBinding(.rightCmd, [FocusCommand.new(direction: .right)]),
                ],
            ),
        ]
        try await activateMode(mainModeId)

        let leftAltDown: NSEvent.ModifierFlags = [.option, TapModifierKey.leftAlt.deviceSpecificModifierFlag]
        let rightCmdDown: NSEvent.ModifierFlags = [.command, TapModifierKey.rightCmd.deviceSpecificModifierFlag]
        noteTapBindingFlagsChanged(keyCode: 58, modifierFlags: leftAltDown)
        XCTAssertEqual(tapBindingPressedModifiersForTests(), [.leftAlt])

        noteTapBindingFlagsChanged(keyCode: 58, modifierFlags: leftAltDown)
        XCTAssertEqual(tapBindingPressedModifiersForTests(), [.leftAlt])

        noteTapBindingFlagsChanged(keyCode: 58, modifierFlags: [])
        XCTAssertTrue(tapBindingPressedModifiersForTests().isEmpty)

        noteTapBindingFlagsChanged(keyCode: 54, modifierFlags: rightCmdDown)
        XCTAssertEqual(tapBindingPressedModifiersForTests(), [.rightCmd])

        // Simulate macOS missing the right-cmd release event. The next modifier
        // event snapshot says only left-alt is down, so stale right-cmd state
        // must be cleared; otherwise tap bindings stop launching after a while.
        noteTapBindingFlagsChanged(keyCode: 58, modifierFlags: leftAltDown)
        XCTAssertEqual(tapBindingPressedModifiersForTests(), [.leftAlt])
    }

    func testBindingEqualityChecksCommandCount() {
        let focusLeft = FocusCommand.new(direction: .left)
        let focusRight = FocusCommand.new(direction: .right)
        let shortHotkey = HotkeyBinding(.option, .h, [focusLeft])
        let longHotkey = HotkeyBinding(.option, .h, [focusLeft, focusRight])
        let shortTap = TapBinding(.leftAlt, [focusLeft])
        let longTap = TapBinding(.leftAlt, [focusLeft, focusRight])

        XCTAssertNotEqual(shortHotkey, longHotkey)
        XCTAssertNotEqual(shortTap, longTap)
    }

    func testWindowDetectedCallbackEqualityChecksCommandCount() {
        let matcher = WindowDetectedCallbackMatcher(appId: "com.example.app")
        let short = WindowDetectedCallback(
            matcher: matcher,
            rawRun: [FocusCommand.new(direction: .left)],
        )
        let long = WindowDetectedCallback(
            matcher: matcher,
            rawRun: [FocusCommand.new(direction: .left), FocusCommand.new(direction: .right)],
        )

        XCTAssertNotEqual(short, long)
    }

    func testModesMustContainDefaultModeError() {
        let (config, errors) = parseConfig(
            """
            [mode.foo.binding]
                alt-h = 'focus left'
            """,
        )
        assertEquals(
            errors.descriptions,
            ["mode: Please specify \'main\' mode"],
        )
        assertEquals(config.modes[mainModeId], nil)
    }

    func testHotkeyParseError() {
        let (config, errors) = parseConfig(
            """
            [mode.main.binding]
                alt-hh = 'focus left'
                aalt-j = 'focus down'
                alt-k = 'focus up'
            """,
        )
        assertEquals(
            errors.descriptions,
            [
                "mode.main.binding.aalt-j: Can\'t parse modifiers in \'aalt-j\' binding",
                "mode.main.binding.alt-hh: Can\'t parse the key in \'alt-hh\' binding",
            ],
        )
        let binding = HotkeyBinding(.option, .k, [FocusCommand.new(direction: .up)])
        assertEquals(
            config.modes[mainModeId],
            Mode(bindings: [binding.descriptionWithKeyCode: binding], tapBindings: [:]),
        )
    }

    func testTapBindingParseError() {
        let (config, errors) = parseConfig(
            """
            [mode.main.binding-tap]
                unicorn = 'focus left'
            """,
        )
        assertEquals(
            errors.descriptions,
            [
                "mode.main.binding-tap.unicorn: Unsupported tap binding key 'unicorn'. Supported keys: left-alt, right-alt, left-cmd, right-cmd, left-ctrl, right-ctrl, left-shift, right-shift",
            ],
        )
        assertEquals(config.modes[mainModeId], Mode(bindings: [:], tapBindings: [:]))
    }

    func testTapModifierKeyUsesSideSpecificModifierFlags() {
        let leftAltFlags: NSEvent.ModifierFlags = [
            .option,
            NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELALTKEYMASK)),
        ]
        let rightCmdFlags: NSEvent.ModifierFlags = [
            .command,
            NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCMDKEYMASK)),
        ]

        XCTAssertTrue(TapModifierKey.leftAlt.isPressed(in: leftAltFlags))
        XCTAssertFalse(TapModifierKey.rightAlt.isPressed(in: leftAltFlags))
        XCTAssertTrue(TapModifierKey.rightCmd.isPressed(in: rightCmdFlags))
        XCTAssertFalse(TapModifierKey.leftCmd.isPressed(in: rightCmdFlags))
        XCTAssertTrue(TapModifierKey.leftAlt.isPressed(in: .option))
    }

    func testPermanentWorkspaceNames() {
        let (config, errors) = parseConfig(
            """
            [mode.main.binding]
                alt-1 = 'workspace 1'
                alt-2 = 'workspace 2'
                alt-3 = ['workspace 3']
                alt-4 = ['workspace 4', 'focus left']
            """,
        )
        assertEquals(errors.descriptions, [])
        assertEquals(config.persistentWorkspaces.sorted(), ["1", "2", "3", "4"])
    }

    func testUnknownTopLevelKeyParseError() {
        let (config, errors) = parseConfig(
            """
            unknownKey = true
            enable-normalization-flatten-containers = false
            """,
        )
        assertEquals(
            errors.descriptions,
            ["unknownKey: Unknown top-level key"],
        )
        assertEquals(config.enableNormalizationFlattenContainers, false)
    }

    func testUnknownKeyParseError() {
        let (config, errors) = parseConfig(
            """
            enable-normalization-flatten-containers = false
            [gaps]
                unknownKey = true
            """,
        )
        assertEquals(
            errors.descriptions,
            ["gaps.unknownKey: Unknown key"],
        )
        assertEquals(config.enableNormalizationFlattenContainers, false)
    }

    func testTypeMismatch() {
        let (_, errors) = parseConfig(
            """
            enable-normalization-flatten-containers = 'true'
            """,
        )
        assertEquals(
            errors.descriptions,
            ["enable-normalization-flatten-containers: Expected type is \'bool\'. But actual type is \'string\'"],
        )
    }

    func testTomlParseError() {
        let (_, errors) = parseConfig("true")
        assertEquals(
            errors.descriptions,
            ["Error while parsing key-value pair: encountered end-of-file (at line 1, column 5)"],
        )
    }

    func testMoveWorkspaceToMonitorCommandParsing() {
        XCTAssertTrue(parseCommand("move-workspace-to-monitor --wrap-around next").cmdOrNil is MoveWorkspaceToMonitorCommand)
        XCTAssertTrue(parseCommand("move-workspace-to-display --wrap-around next").cmdOrNil is MoveWorkspaceToMonitorCommand)
    }

    func testParseTiles() {
        let command = parseCommand("layout tiles h_tiles v_tiles tab-group h_tab_group v_tab_group").cmdOrNil
        guard let command = command as? LayoutCommand else {
            XCTFail("Expected layout command")
            return
        }
        assertEquals(command.args.toggleBetween.val, [.tiles, .h_tiles, .v_tiles, .tabGroup, .hTabGroup, .vTabGroup])

        guard case .help = parseCommand("layout tiles -h") else {
            XCTFail()
            return
        }
    }

    func testSplitCommandAndFlattenContainersNormalization() {
        let (_, errors) = parseConfig(
            """
            enable-normalization-flatten-containers = true
            [mode.main.binding]
            [mode.foo.binding]
                alt-s = 'split horizontal'
            """,
        )
        assertEquals(
            errors.descriptions,
            ["""
                The config contains:
                1. usage of 'split' command
                2. enable-normalization-flatten-containers = true
                These two settings don't play nicely together. 'split' command has no effect when enable-normalization-flatten-containers is disabled.

                My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
                """],
        )
    }

    func testParseWorkspaceToMonitorAssignment() {
        let (parsed, errors) = parseConfig(
            """
            [workspace-to-monitor-force-assignment]
                workspace_name_1 = 1                            # Sequence number of the monitor (from left to right, 1-based indexing)
                workspace_name_2 = 'main'                       # main monitor
                workspace_name_3 = 'secondary'                  # non-main monitor (in case when there are only two monitors)
                workspace_name_4 = 'built-in'                   # case insensitive regex substring
                workspace_name_5 = '^built-in retina display$'  # case insensitive regex match
                workspace_name_6 = ['secondary', 1]             # you can specify multiple patterns. The first matching pattern will be used
                7 = "foo"
                w7 = ['', 'main']
                w8 = 0
                workspace_name_x = '2'                          # Sequence number of the monitor (from left to right, 1-based indexing)
            """,
        )
        assertEquals(
            parsed.workspaceToMonitorForceAssignment,
            [
                "workspace_name_1": [.sequenceNumber(1)],
                "workspace_name_2": [.main],
                "workspace_name_3": [.secondary],
                "workspace_name_4": [.caseSensitivePattern("built-in")!],
                "workspace_name_5": [.caseSensitivePattern("^built-in retina display$")!],
                "workspace_name_6": [.secondary, .sequenceNumber(1)],
                "workspace_name_x": [.sequenceNumber(2)],
                "7": [.caseSensitivePattern("foo")!],
                "w7": [.main],
                "w8": [],
            ],
        )
        assertEquals([
            "workspace-to-monitor-force-assignment.w7[0]: Empty string is an illegal monitor description",
            "workspace-to-monitor-force-assignment.w8: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
        ], errors.descriptions)
        assertEquals([:], defaultConfig.workspaceToMonitorForceAssignment)
    }

}
