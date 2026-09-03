import SwiftUI

struct ShortcutBehaviorSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var automaticallyTileNewWindows = config.automaticallyTileNewWindows
    @State private var autoAddNewWindowsToTabGroup = config.autoAddNewWindowsToTabGroup
    @State private var enableShakeToToggleTiling = config.enableShakeToToggleTiling
    @State private var automaticallyUnhideMacosHiddenApps = config.automaticallyUnhideMacosHiddenApps
    @State private var autoReloadConfig = config.autoReloadConfig
    @State private var startAtLogin = config.startAtLogin
    @State private var defaultLayout = config.defaultRootContainerLayout
    @State private var defaultOrientation = config.defaultRootContainerOrientation
    @State private var flattenContainers = config.enableNormalizationFlattenContainers
    @State private var normalizeNestedContainers = config.enableNormalizationOppositeOrientationForNestedContainers
    @State private var shortcutsPreset = config.shortcutsPreset.rawValue
    @State private var persistentWorkspaces = config.persistentWorkspaces.joined(separator: ", ")

    var body: some View {
        SettingsScrollView {
            SettingsSection("New windows") {
                SettingsToggle("Tile new windows automatically", isOn: $automaticallyTileNewWindows, help: "Place new windows in the current tiled layout.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
                SettingsToggle("Add new windows to the current tab group", isOn: $autoAddNewWindowsToTabGroup, help: "Keep new windows in the selected stack instead of creating a new tile.") { persistRootBool("auto-add-new-windows-to-tab-group", autoAddNewWindowsToTabGroup) }
                SettingsToggle("Unhide macOS-hidden apps", isOn: $automaticallyUnhideMacosHiddenApps, help: "Restore apps macOS has hidden when they receive focus.") { persistRootBool("automatically-unhide-macos-hidden-apps", automaticallyUnhideMacosHiddenApps) }
            }
            SettingsSection("Interaction") {
                SettingsToggle("Shake to toggle tiling", isOn: $enableShakeToToggleTiling, help: "Shake a window by its title bar to switch between floating and tiled.") { persistRootBool("enable-shake-to-toggle-tiling", enableShakeToToggleTiling) }
                SettingsToggle("Flatten matching containers", isOn: $flattenContainers, help: "Simplify adjacent containers with the same layout orientation.") { persistRootBool("enable-normalization-flatten-containers", flattenContainers) }
                SettingsToggle("Normalize nested orientations", isOn: $normalizeNestedContainers, help: "Avoid nested tiled containers with the same orientation.") { persistRootBool("enable-normalization-opposite-orientation-for-nested-containers", normalizeNestedContainers) }
            }
            SettingsSection("Startup") {
                SettingsToggle("Start at login", isOn: $startAtLogin, help: "Launch WinMux after you sign in.") { persistRootBool("start-at-login", startAtLogin) }
                SettingsToggle("Reload config when it changes", isOn: $autoReloadConfig, help: "Apply valid edits saved from another editor automatically.") { persistRootBool("auto-reload-config", autoReloadConfig) }
            }
            SettingsSection("Default layout") {
                SettingsPicker("Root layout", selection: $defaultLayout, help: "Used for new workspaces.") {
                    Text("Tiles").tag(Layout.tiles)
                    Text("Tab group").tag(Layout.tabGroup)
                } onChange: { persistRootString("default-root-container-layout", defaultLayout.rawValue) }
                SettingsPicker("Root orientation", selection: $defaultOrientation, help: "Controls how new tiled containers split.") {
                    Text("Automatic").tag(DefaultContainerOrientation.auto)
                    Text("Horizontal").tag(DefaultContainerOrientation.horizontal)
                    Text("Vertical").tag(DefaultContainerOrientation.vertical)
                } onChange: { persistRootString("default-root-container-orientation", defaultOrientation.rawValue) }
                SettingsPicker("Shortcut preset", selection: $shortcutsPreset, help: "Install the built-in default shortcut set, or use your own.") {
                    Text("Custom").tag("none")
                    Text("Rectangle").tag("rectangle")
                } onChange: { persistRootString("shortcuts-preset", shortcutsPreset) }
            }
            SettingsSection("Workspaces") {
                SettingsTextField("Persistent workspaces", text: $persistentWorkspaces, help: "Comma-separated workspace names that remain available when empty.") {
                    persistConfig(section: nil, key: "persistent-workspaces", value: tomlStringArray(persistentWorkspaces))
                }
            }
        }
    }

    private func persistRootBool(_ key: String, _ value: Bool) { persistConfig(section: nil, key: key, value: value ? "true" : "false") }
    private func persistRootString(_ key: String, _ value: String) { persistConfig(section: nil, key: key, value: "'\(value)'") }
    private func persistConfig(section: String?, key: String, value: String) {
        persistSettingsConfig(section: section, key: key, renderedValue: value, model: model)
    }
}

struct ShortcutAppearanceSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var sidebarEnabled = config.workspaceSidebar.enabled
    @State private var sidebarFocusEnabled = config.workspaceSidebar.enableFocus
    @State private var sidebarStayOnTop = config.workspaceSidebar.stayOnTop
    @State private var sidebarAutoHide = config.workspaceSidebar.autoHide
    @State private var sidebarAlwaysExpanded = config.workspaceSidebar.alwaysExpanded
    @State private var showStatusPills = config.workspaceSidebar.showStatusPills
    @State private var showClock = config.workspaceSidebar.showClock
    @State private var showSeconds = config.workspaceSidebar.showSeconds
    @State private var showDate = config.workspaceSidebar.showDate
    @State private var showWeekday = config.workspaceSidebar.showWeekday
    @State private var chromeStyle = config.workspaceSidebar.chromeStyle
    @State private var solidChromeColor = config.workspaceSidebar.solidChromeColor
    @State private var solidChromeCustomColor = config.workspaceSidebar.solidChromeCustomColor
    @State private var sidebarWidth = config.workspaceSidebar.width
    @State private var collapsedWidth = config.workspaceSidebar.collapsedWidth
    @State private var tabEnabled = config.windowTabs.enabled
    @State private var tabHeight = config.windowTabs.height
    @State private var tabPadding = config.tabGroupPadding
    @State private var menuBarReserveHeight = config.workspaceSidebar.menuBarReserveHeight
    @State private var projectDeletionAction = config.workspaceSidebar.projectDeletionAction
    @State private var innerHorizontalGap = settingsConstantValue(config.gaps.inner.horizontal)
    @State private var innerVerticalGap = settingsConstantValue(config.gaps.inner.vertical)
    @State private var outerLeftGap = settingsConstantValue(config.gaps.outer.left)
    @State private var outerRightGap = settingsConstantValue(config.gaps.outer.right)
    @State private var outerTopGap = settingsConstantValue(config.gaps.outer.top)
    @State private var outerBottomGap = settingsConstantValue(config.gaps.outer.bottom)

    var body: some View {
        SettingsScrollView {
            SettingsSection("Chrome") {
                SettingsPicker("Style", selection: $chromeStyle, help: "Apply Liquid Glass or an opaque solid color to the sidebar, tab groups, and switcher. Settings keep their own appearance.") {
                    Text("Liquid Glass").tag(ChromeStyle.liquidGlass)
                    Text("Solid color").tag(ChromeStyle.solid)
                } onChange: { persist("workspace-sidebar", "chrome-style", "'\(chromeStyle.rawValue)'") }
                SettingsSolidColorPalette(
                    selection: $solidChromeColor,
                    customColor: $solidChromeCustomColor,
                    isEnabled: chromeStyle == .solid,
                    onSelectionChange: { persist("workspace-sidebar", "solid-chrome-color", "'\(solidChromeColor.rawValue)'") },
                    onCustomColorChange: { persist("workspace-sidebar", "solid-chrome-custom-color", "'\(solidChromeCustomColor)'") },
                )
            }
            SettingsSection("Sidebar") {
                SettingsToggle("Show sidebar", isOn: $sidebarEnabled, help: "Show the workspace rail on configured displays.") { sidebarBool("enabled", sidebarEnabled) }
                SettingsToggle("Focus sidebar monitor only", isOn: $sidebarFocusEnabled, help: "Show the sidebar only on the focused monitor when monitor scope allows it.") { sidebarBool("enable-focus", sidebarFocusEnabled) }
                SettingsToggle("Keep sidebar above Dock", isOn: $sidebarStayOnTop, help: "Keep the sidebar above the Dock. Turn this off to let the Dock appear over it.") { sidebarBool("stay-on-top", sidebarStayOnTop) }
                SettingsToggle("Reveal sidebar at the display edge", isOn: $sidebarAutoHide, help: "Hide the compact rail until the pointer reaches the left edge.") { sidebarBool("auto-hide", sidebarAutoHide) }
                SettingsToggle("Keep sidebar expanded", isOn: $sidebarAlwaysExpanded, help: "Reserve the full sidebar width for tiled windows.") { sidebarBool("always-expanded", sidebarAlwaysExpanded) }
                SettingsStepper("Expanded width", value: $sidebarWidth, range: 120...480, help: "Width of the fully expanded sidebar.") { sidebarInt("width", sidebarWidth) }
                SettingsStepper("Collapsed width", value: $collapsedWidth, range: 28...120, help: "Width of the compact sidebar rail.") { sidebarInt("collapsed-width", collapsedWidth) }
                SettingsStepper("Menu bar reserve", value: $menuBarReserveHeight, range: 0...72, help: "Use 0 px when the macOS menu bar auto-hides.") { sidebarInt("menu-bar-reserve-height", menuBarReserveHeight) }
                SettingsPicker("Deleting projects", selection: $projectDeletionAction, help: "Choose what happens to the project's windows.") {
                    Text("Close project windows").tag(WorkspaceProjectDeletionAction.closeWindows)
                    Text("Move windows elsewhere").tag(WorkspaceProjectDeletionAction.moveWindowsToFallback)
                } onChange: { persist("workspace-sidebar", "project-deletion-action", "'\(projectDeletionAction.rawValue)'") }
            }
            SettingsSection("Sidebar content") {
                SettingsToggle("Show status pills", isOn: $showStatusPills) { sidebarBool("show-status-pills", showStatusPills) }
                SettingsToggle("Show clock", isOn: $showClock) { sidebarBool("show-clock", showClock) }
                SettingsToggle("Show seconds", isOn: $showSeconds) { sidebarBool("show-seconds", showSeconds) }
                SettingsToggle("Show date", isOn: $showDate) { sidebarBool("show-date", showDate) }
                SettingsToggle("Show weekday", isOn: $showWeekday) { sidebarBool("show-weekday", showWeekday) }
            }
            SettingsSection("Window tabs") {
                SettingsToggle("Show tab strips", isOn: $tabEnabled, help: "Display browser-like tabs for stacked windows.") { persist("window-tabs", "enabled", tabEnabled ? "true" : "false") }
                SettingsStepper("Tab strip height", value: $tabHeight, range: 21...80, help: "Height of the window tab strip.") { persist("window-tabs", "height", "\(tabHeight)") }
                SettingsStepper("Tab group padding", value: $tabPadding, range: 0...80, help: "Space around tab groups.") { persist(nil, "tab-group-padding", "\(tabPadding)") }
            }
            SettingsSection("Tiling gaps") {
                SettingsStepper("Inner horizontal", value: $innerHorizontalGap, range: 0...80, help: "Space between windows side by side.") { persist("gaps", "inner.horizontal", "\(innerHorizontalGap)") }
                SettingsStepper("Inner vertical", value: $innerVerticalGap, range: 0...80, help: "Space between vertically stacked windows.") { persist("gaps", "inner.vertical", "\(innerVerticalGap)") }
                SettingsStepper("Outer left", value: $outerLeftGap, range: 0...120, help: "Inset at the left display edge.") { persist("gaps", "outer.left", "\(outerLeftGap)") }
                SettingsStepper("Outer right", value: $outerRightGap, range: 0...120, help: "Inset at the right display edge.") { persist("gaps", "outer.right", "\(outerRightGap)") }
                SettingsStepper("Outer top", value: $outerTopGap, range: 0...120, help: "Inset at the top display edge.") { persist("gaps", "outer.top", "\(outerTopGap)") }
                SettingsStepper("Outer bottom", value: $outerBottomGap, range: 0...120, help: "Inset at the bottom display edge.") { persist("gaps", "outer.bottom", "\(outerBottomGap)") }
            }
        }
    }

    private func sidebarBool(_ key: String, _ value: Bool) { persist("workspace-sidebar", key, value ? "true" : "false") }
    private func sidebarInt(_ key: String, _ value: Int) { persist("workspace-sidebar", key, "\(value)") }
    private func persist(_ section: String?, _ key: String, _ value: String) { persistSettingsConfig(section: section, key: key, renderedValue: value, model: model) }
}

struct ShortcutAutomationSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var workspaceCommands = ""
    @State private var focusCommands = ""
    @State private var monitorCommands = ""
    @State private var modeCommands = ""
    @State private var configurationText = ""

    var body: some View {
        SettingsScrollView {
            SettingsSection("Event actions") {
                SettingsMultilineField("On workspace change", text: $workspaceCommands, help: "One command per line. Commands run after changing workspaces.") { saveCommands("exec-on-workspace-change", workspaceCommands) }
                SettingsMultilineField("On focus change", text: $focusCommands, help: "One command per line. Commands run after the focused window changes.") { saveCommands("on-focus-changed", focusCommands) }
                SettingsMultilineField("On focused monitor change", text: $monitorCommands, help: "One command per line. Commands run after the active display changes.") { saveCommands("on-focused-monitor-changed", monitorCommands) }
                SettingsMultilineField("On mode change", text: $modeCommands, help: "One command per line. Commands run after a mode changes.") { saveCommands("on-mode-changed", modeCommands) }
            }
            SettingsSection("Advanced rules") {
                Text("Window-detected rules, execution environment variables, key remapping, custom modes, tap bindings, sequence bindings, and workspace-to-monitor assignments are all available below as TOML blocks. This keeps their variable-length rules editable without hiding any option.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                Button("Load all advanced rules") { configurationText = currentSettingsConfigText() }
                    .padding(.horizontal, 12)
                TextEditor(text: $configurationText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 260)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 12)
                HStack {
                    Button("Validate rules") { validate() }
                    Button("Save all advanced rules") { saveAll() }
                        .keyboardShortcut("s", modifiers: [.command, .option])
                }
                .padding(12)
            }
        }
        .task { loadCommands() }
        .onChange(of: model.settingsRevision) { _ in loadCommands() }
    }

    private func loadCommands() {
        workspaceCommands = config.execOnWorkspaceChange.joined(separator: "\n")
        focusCommands = config.onFocusChanged.map { $0.args.description }.joined(separator: "\n")
        monitorCommands = config.onFocusedMonitorChanged.map { $0.args.description }.joined(separator: "\n")
        modeCommands = config.onModeChanged.map { $0.args.description }.joined(separator: "\n")
    }

    private func saveCommands(_ key: String, _ commands: String) {
        persistSettingsConfig(section: nil, key: key, renderedValue: tomlStringArray(commands), model: model)
    }

    private func validate() {
        let errors = parseConfig(configurationText).errors
        model.errorMessage = errors.isEmpty ? nil : errors.map(\.description).joined(separator: "\n\n")
    }

    private func saveAll() {
        let errors = parseConfig(configurationText).errors
        guard errors.isEmpty else { model.errorMessage = errors.map(\.description).joined(separator: "\n\n"); return }
        Task { @MainActor in
            do {
                let url = preferredEditableConfigUrl()
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try configurationText.write(to: url, atomically: true, encoding: .utf8)
                guard try await reloadConfig(forceConfigUrl: url) else { throw NSError(domain: "WinMux", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved the rules, but could not reload the config."]) }
                model.reload()
            } catch { model.errorMessage = error.localizedDescription }
        }
    }
}

private struct SettingsScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: StrokeToken.hairline)
            }
        }
    }
}

private struct SettingsToggle: View {
    let title: String; @Binding var isOn: Bool; var help: String? = nil; let save: () -> Void
    init(_ title: String, isOn: Binding<Bool>, help: String? = nil, save: @escaping () -> Void) { self.title = title; _isOn = isOn; self.help = help; self.save = save }
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .help(help ?? title)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 14)
        }
        .onChange(of: isOn) { _ in save() }
    }
}

private struct SettingsStepper: View {
    let title: String; @Binding var value: Int; let range: ClosedRange<Int>; let help: String; let save: () -> Void
    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, help: String, save: @escaping () -> Void) {
        self.title = title
        _value = value
        self.range = range
        self.help = help
        self.save = save
    }
    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .frame(width: 96)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .help(help)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 14)
        }
        .onChange(of: value) { _ in save() }
    }
}

private struct SettingsTextField: View {
    let title: String; @Binding var text: String; let help: String; let save: () -> Void
    init(_ title: String, text: Binding<String>, help: String, save: @escaping () -> Void) { self.title = title; _text = text; self.help = help; self.save = save }
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 230)
                .onSubmit(save)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .help(help)
    }
}

private struct SettingsMultilineField: View {
    let title: String; @Binding var text: String; let help: String; let save: () -> Void
    init(_ title: String, text: Binding<String>, help: String, save: @escaping () -> Void) { self.title = title; _text = text; self.help = help; self.save = save }
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title); Text(help).font(.caption).foregroundStyle(.secondary); TextEditor(text: $text).font(.system(size: 12, design: .monospaced)).frame(minHeight: 50).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor))); Button("Apply") { save() }.controlSize(.small) }.padding(12) }
}

private struct SettingsPicker<Selection: Hashable, Content: View>: View {
    let title: String; @Binding var selection: Selection; let help: String; @ViewBuilder let content: Content; let onChange: () -> Void
    init(_ title: String, selection: Binding<Selection>, help: String, @ViewBuilder content: () -> Content, onChange: @escaping () -> Void) { self.title = title; _selection = selection; self.help = help; self.content = content(); self.onChange = onChange }
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: $selection, content: { content })
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .help(help)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 14)
        }
        .onChange(of: selection) { _ in onChange() }
    }
}

private struct SettingsSolidColorPalette: View {
    @Binding var selection: ChromeSolidColor
    @Binding var customColor: String
    let isEnabled: Bool
    let onSelectionChange: () -> Void
    let onCustomColorChange: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(minimum: 40), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Solid color")
            Text("Choose an opaque chrome color.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ChromeSolidColor.allCases) { color in
                    Button {
                        selection = color
                    } label: {
                        GlassSurface(
                            shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                            hasBorder: false,
                            style: .solid,
                            solidColor: color == .custom ? Color(chromeHex: customColor) : color.color,
                        )
                            .frame(height: 42)
                            .overlay {
                                if selection == color {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.4), radius: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(selection == color ? .isSelected : [])
                }
            }
            if selection == .custom {
                ColorPicker("Custom color", selection: Binding(
                    get: { Color(chromeHex: customColor) },
                    set: { customColor = $0.chromeHex },
                ), supportsOpacity: false)
            }
        }
        .padding(14)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 14)
        }
        .onChange(of: selection) { _ in onSelectionChange() }
        .onChange(of: customColor) { _ in
            guard selection == .custom else { return }
            onCustomColorChange()
        }
    }
}

@MainActor
private func persistSettingsConfig(section: String?, key: String, renderedValue: String, model: ShortcutSettingsModel) {
    Task { @MainActor in
        do {
            let url = preferredEditableConfigUrl()
            let current = (try? String(contentsOf: url, encoding: .utf8)) ?? starterConfigText()
            let updated = updateSettingsScalarConfig(in: current, section: section, key: key, renderedValue: renderedValue)
            let parsed = parseConfig(updated)
            guard parsed.errors.isEmpty else {
                throw NSError(domain: "WinMux", code: 1, userInfo: [NSLocalizedDescriptionKey: parsed.errors.map(\.description).joined(separator: "\n")])
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: url, atomically: true, encoding: .utf8)
            guard try await reloadConfig(forceConfigUrl: url) else { throw NSError(domain: "WinMux", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved the setting, but could not reload the config."]) }
            model.reload()
            WorkspaceSidebarPanel.refreshAll()
        } catch { model.errorMessage = error.localizedDescription }
    }
}

func updateSettingsScalarConfig(in text: String, section: String?, key: String, renderedValue: String) -> String {
    let header = section.map { "[\($0)]" }
    var lines = text.components(separatedBy: "\n")
    let start: Int
    let end: Int
    if let header, let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
        start = index + 1
        end = lines[start...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) ?? lines.endIndex
    } else if let header {
        if !lines.last.map({ $0.isEmpty })! { lines.append("") }
        lines.append(header)
        lines.append("    \(key) = \(renderedValue)")
        return lines.joined(separator: "\n")
    } else {
        start = 0
        end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) ?? lines.endIndex
    }
    for index in start..<end where settingsKey(in: lines[index]) == key {
        let indent = String(lines[index].prefix(while: { $0.isWhitespace }))
        lines[index] = "\(indent)\(key) = \(renderedValue)"
        return lines.joined(separator: "\n")
    }
    lines.insert("\(section == nil ? "" : "    ")\(key) = \(renderedValue)", at: start)
    return lines.joined(separator: "\n")
}

private func settingsKey(in line: String) -> String? {
    let line = line.trimmingCharacters(in: .whitespaces)
    guard !line.hasPrefix("#"), let equal = line.firstIndex(of: "=") else { return nil }
    return String(line[..<equal]).trimmingCharacters(in: .whitespaces)
}

private func tomlStringArray(_ text: String) -> String {
    let values = text.split(whereSeparator: \ .isNewline).map { value in
        "\"\(value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
    return "[\(values.joined(separator: ", "))]"
}

private func settingsConstantValue(_ value: DynamicConfigValue<Int>) -> Int {
    switch value {
        case .constant(let value): value
        case .perMonitor(_, let `default`): `default`
    }
}

@MainActor
private func currentSettingsConfigText() -> String {
    let url = preferredEditableConfigUrl()
    return (try? String(contentsOf: url, encoding: .utf8)) ?? starterConfigText()
}
