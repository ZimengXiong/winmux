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

    var body: some View {
        SettingsScrollView {
            SettingsSection("New windows") {
                SettingsToggle("Tile new windows automatically", isOn: $automaticallyTileNewWindows, help: "Place new windows in the current tiled layout.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
                SettingsToggle("Add new windows to the current tab group", isOn: $autoAddNewWindowsToTabGroup, help: "Keep new windows in the selected stack instead of creating a new tile.") { persistRootBool("auto-add-new-windows-to-tab-group", autoAddNewWindowsToTabGroup) }
                SettingsToggle("Unhide macOS-hidden apps", isOn: $automaticallyUnhideMacosHiddenApps, help: "Restore apps macOS has hidden when they receive focus.") { persistRootBool("automatically-unhide-macos-hidden-apps", automaticallyUnhideMacosHiddenApps) }
            }
            SettingsSection("Interaction") {
                SettingsToggle("Shake to toggle tiling", isOn: $enableShakeToToggleTiling, help: "Shake a window by its title bar to switch between floating and tiled.") { persistRootBool("enable-shake-to-toggle-tiling", enableShakeToToggleTiling) }
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
    @State private var sidebarAutoHide = config.workspaceSidebar.autoHide
    @State private var sidebarAlwaysExpanded = config.workspaceSidebar.alwaysExpanded
    @State private var showStatusPills = config.workspaceSidebar.showStatusPills
    @State private var showClock = config.workspaceSidebar.showClock
    @State private var showSeconds = config.workspaceSidebar.showSeconds
    @State private var showDate = config.workspaceSidebar.showDate
    @State private var showWeekday = config.workspaceSidebar.showWeekday
    @State private var liquidGlass = config.workspaceSidebar.useLiquidGlass
    @State private var sidebarWidth = config.workspaceSidebar.width
    @State private var collapsedWidth = config.workspaceSidebar.collapsedWidth
    @State private var tabEnabled = config.windowTabs.enabled
    @State private var tabHeight = config.windowTabs.height
    @State private var tabPadding = config.tabGroupPadding

    var body: some View {
        SettingsScrollView {
            SettingsSection("Sidebar") {
                SettingsToggle("Show sidebar", isOn: $sidebarEnabled, help: "Show the workspace rail on configured displays.") { sidebarBool("enabled", sidebarEnabled) }
                SettingsToggle("Reveal sidebar at the display edge", isOn: $sidebarAutoHide, help: "Hide the compact rail until the pointer reaches the left edge.") { sidebarBool("auto-hide", sidebarAutoHide) }
                SettingsToggle("Keep sidebar expanded", isOn: $sidebarAlwaysExpanded, help: "Reserve the full sidebar width for tiled windows.") { sidebarBool("always-expanded", sidebarAlwaysExpanded) }
                SettingsStepper("Expanded width", value: $sidebarWidth, range: 120...480, help: "Width of the fully expanded sidebar.") { sidebarInt("width", sidebarWidth) }
                SettingsStepper("Collapsed width", value: $collapsedWidth, range: 28...120, help: "Width of the compact sidebar rail.") { sidebarInt("collapsed-width", collapsedWidth) }
            }
            SettingsSection("Sidebar content") {
                SettingsToggle("Show status pills", isOn: $showStatusPills) { sidebarBool("show-status-pills", showStatusPills) }
                SettingsToggle("Show clock", isOn: $showClock) { sidebarBool("show-clock", showClock) }
                SettingsToggle("Show seconds", isOn: $showSeconds) { sidebarBool("show-seconds", showSeconds) }
                SettingsToggle("Show date", isOn: $showDate) { sidebarBool("show-date", showDate) }
                SettingsToggle("Show weekday", isOn: $showWeekday) { sidebarBool("show-weekday", showWeekday) }
                SettingsToggle("Use Liquid Glass", isOn: $liquidGlass, help: "Uses native Liquid Glass on supported macOS versions.") { sidebarBool("use-liquid-glass", liquidGlass) }
            }
            SettingsSection("Window tabs") {
                SettingsToggle("Show tab strips", isOn: $tabEnabled, help: "Display browser-like tabs for stacked windows.") { persist("window-tabs", "enabled", tabEnabled ? "true" : "false") }
                SettingsStepper("Tab strip height", value: $tabHeight, range: 21...80, help: "Height of the window tab strip.") { persist("window-tabs", "height", "\(tabHeight)") }
                SettingsStepper("Tab group padding", value: $tabPadding, range: 0...80, help: "Space around tab groups.") { persist(nil, "tab-group-padding", "\(tabPadding)") }
            }
        }
    }

    private func sidebarBool(_ key: String, _ value: Bool) { persist("workspace-sidebar", key, value ? "true" : "false") }
    private func sidebarInt(_ key: String, _ value: Int) { persist("workspace-sidebar", key, "\(value)") }
    private func persist(_ section: String?, _ key: String, _ value: String) { persistSettingsConfig(section: section, key: key, renderedValue: value, model: model) }
}

private struct SettingsScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 20) { content }.padding(20) } }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            VStack(spacing: 0) { content }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5))
        }
    }
}

private struct SettingsToggle: View {
    let title: String; @Binding var isOn: Bool; var help: String? = nil; let save: () -> Void
    init(_ title: String, isOn: Binding<Bool>, help: String? = nil, save: @escaping () -> Void) { self.title = title; _isOn = isOn; self.help = help; self.save = save }
    var body: some View { Toggle(isOn: $isOn) { VStack(alignment: .leading, spacing: 1) { Text(title); if let help { Text(help).font(.caption).foregroundStyle(.secondary) } } }.toggleStyle(.switch).padding(.vertical, 7).padding(.horizontal, 12).onChange(of: isOn) { _ in save() } }
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
    var body: some View { HStack { VStack(alignment: .leading, spacing: 1) { Text(title); Text(help).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(value) px").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary); Stepper("", value: $value, in: range).labelsHidden() }.padding(.vertical, 7).padding(.horizontal, 12).onChange(of: value) { _ in save() } }
}

private struct SettingsPicker<Selection: Hashable, Content: View>: View {
    let title: String; @Binding var selection: Selection; let help: String; @ViewBuilder let content: Content; let onChange: () -> Void
    init(_ title: String, selection: Binding<Selection>, help: String, @ViewBuilder content: () -> Content, onChange: @escaping () -> Void) { self.title = title; _selection = selection; self.help = help; self.content = content(); self.onChange = onChange }
    var body: some View { HStack { VStack(alignment: .leading, spacing: 1) { Text(title); Text(help).font(.caption).foregroundStyle(.secondary) }; Spacer(); Picker("", selection: $selection, content: { content }).labelsHidden().pickerStyle(.menu).frame(width: 150) }.padding(.vertical, 7).padding(.horizontal, 12).onChange(of: selection) { _ in onChange() } }
}

@MainActor
private func persistSettingsConfig(section: String?, key: String, renderedValue: String, model: ShortcutSettingsModel) {
    Task { @MainActor in
        do {
            let url = preferredEditableConfigUrl()
            let current = (try? String(contentsOf: url, encoding: .utf8)) ?? starterConfigText()
            let updated = updateSettingsScalarConfig(in: current, section: section, key: key, renderedValue: renderedValue)
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
