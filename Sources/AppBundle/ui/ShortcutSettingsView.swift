import AppKit
import Common
import MASShortcut
import SwiftUI

public let shortcutSettingsWindowId = "\(winMuxAppName).shortcutSettings"

@MainActor
public func getShortcutSettingsWindow(model: ShortcutSettingsModel) -> some Scene {
    SwiftUI.Window("WinMux Settings", id: shortcutSettingsWindowId) {
        ShortcutSettingsView(model: model)
            .frame(minWidth: 720, minHeight: 600)
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
            }
    }
}

@MainActor
public func openShortcutSettingsWindow(_ openWindow: OpenWindowAction) {
    ShortcutSettingsModel.shared.reload()
    if let existingWindow = shortcutSettingsWindow() {
        presentShortcutSettingsWindow(existingWindow)
    } else {
        openWindow(id: shortcutSettingsWindowId)
        DispatchQueue.main.async {
            if let createdWindow = shortcutSettingsWindow() {
                presentShortcutSettingsWindow(createdWindow)
            }
        }
    }
}

enum SettingsSidebarItem: Hashable, Identifiable {
    case managedShortcuts
    case commonShortcuts
    case unmanagedShortcuts
    case general
    case advanced

    var id: Self { self }

    var label: String {
        switch self {
            case .managedShortcuts: "Managed Shortcuts"
            case .commonShortcuts: "Common Shortcuts"
            case .unmanagedShortcuts: "Unmanaged Shortcuts"
            case .general: "General"
            case .advanced: "Advanced"
        }
    }

    var icon: String {
        switch self {
            case .managedShortcuts: "keyboard"
            case .commonShortcuts: "keyboard"
            case .unmanagedShortcuts: "keyboard"
            case .general: "gearshape"
            case .advanced: "slider.horizontal.3"
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var selectedItem: SettingsSidebarItem? = .managedShortcuts

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("Shortcuts") {
                    NavigationLink(value: SettingsSidebarItem.managedShortcuts) {
                        Label(SettingsSidebarItem.managedShortcuts.label, systemImage: SettingsSidebarItem.managedShortcuts.icon)
                    }
                    NavigationLink(value: SettingsSidebarItem.commonShortcuts) {
                        Label(SettingsSidebarItem.commonShortcuts.label, systemImage: SettingsSidebarItem.commonShortcuts.icon)
                    }
                    NavigationLink(value: SettingsSidebarItem.unmanagedShortcuts) {
                        Label(SettingsSidebarItem.unmanagedShortcuts.label, systemImage: SettingsSidebarItem.unmanagedShortcuts.icon)
                    }
                }

                Section("Application") {
                    NavigationLink(value: SettingsSidebarItem.general) {
                        Label(SettingsSidebarItem.general.label, systemImage: SettingsSidebarItem.general.icon)
                    }
                    NavigationLink(value: SettingsSidebarItem.advanced) {
                        Label(SettingsSidebarItem.advanced.label, systemImage: SettingsSidebarItem.advanced.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch selectedItem {
                    case .managedShortcuts:
                        ShortcutCategoryView(model: model, category: .managed)
                    case .commonShortcuts:
                        ShortcutCategoryView(model: model, category: .common)
                    case .unmanagedShortcuts:
                        ShortcutCategoryView(model: model, category: .unmanaged)
                    case .general:
                        ShortcutGeneralView(model: model)
                    case .advanced:
                        ShortcutAdvancedView(model: model)
                    case nil:
                        Text("Select an item")
                }
            }
            .navigationTitle(selectedItem?.label ?? "")
        }
    }
}

struct ShortcutCategoryView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let category: ShortcutSettingsModel.Category

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if let error = model.errorMessage {
                    Text(error)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                let sections = model.sections.filter { $0.category == category && $0.id != "managed-move" }
                ForEach(sections) { section in
                    ShortcutSectionView(model: model, section: section)
                }
            }
            .padding(24)
        }
    }
}

struct ShortcutSectionView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let section: ShortcutSettingsModel.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if section.id != "managed-focus" {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)
                    if let summary = section.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if section.id == "managed-focus" {
                ManagedDirectionalShortcutsView(model: model)
            } else if section.id == "managed-move" {
                EmptyView()
            } else if section.id == "managed-splits" {
                CompassPad(model: model, title: "Split", prefix: "split") {
                    SplitDemoView()
                }
            } else if section.id == "unmanaged" {
                HStack {
                    SnapGridPad(model: model)
                    Spacer()
                }
            } else if section.id == "workspaces" {
                WorkspaceShortcutSectionView(model: model)
            } else {
                VStack(spacing: 0) {
                    ForEach(section.actions.indices, id: \.self) { index in
                        let action = section.actions[index]
                        ShortcutRow(model: model, action: action)
                        if index < section.actions.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }
}

struct ManagedDirectionalShortcutsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var availableWidth: CGFloat = .zero

    private static let horizontalLayoutMinWidth: CGFloat = 880

    var body: some View {
        Group {
            if availableWidth >= Self.horizontalLayoutMinWidth {
                HStack(alignment: .top, spacing: 24) {
                    directionalPad(title: "Focus", prefix: "focus") {
                        FocusDemoView()
                    }

                    directionalPad(title: "Move", prefix: "move") {
                        MoveDemoView()
                    }

                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    directionalPad(title: "Focus", prefix: "focus") {
                        FocusDemoView()
                    }

                    directionalPad(title: "Move", prefix: "move") {
                        MoveDemoView()
                    }
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ManagedDirectionalShortcutsWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(ManagedDirectionalShortcutsWidthKey.self) { width in
            availableWidth = width
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func directionalPad<Demo: View>(
        title: String,
        prefix: String,
        @ViewBuilder demo: () -> Demo
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            CompassPad(model: model, title: title, prefix: prefix, demo: demo)
        }
    }
}

private struct ManagedDirectionalShortcutsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DemoColors {
    static let win1 = Color.blue
    static let win2 = Color.orange
    static let win3 = Color.purple
}

struct DemoContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .frame(width: 100, height: 60)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5))
    }
}

struct FocusDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win1).opacity(phase == 1 ? 1 : 0.3)
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win2).opacity(phase == 2 ? 1 : 0.3)
            }
            .animation(.easeInOut(duration: 0.2), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 4 // 0: reset, 1: left focused, 2: right focused, 3: delay
        }
    }
}

struct MoveDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            GeometryReader { geo in
                let spacing: CGFloat = 4
                let winW = (geo.size.width - spacing) / 2
                let h = geo.size.height
                
                // Left position x: winW / 2
                // Right position x: winW + spacing + winW / 2
                
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win1)
                    .frame(width: winW, height: h)
                    .position(
                        x: phase == 1 ? (winW + spacing + winW / 2) : winW / 2,
                        y: h / 2
                    )
                
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win2)
                    .frame(width: winW, height: h)
                    .position(
                        x: phase == 1 ? winW / 2 : (winW + spacing + winW / 2),
                        y: h / 2
                    )
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3 // 0: A-B, 1: B-A, 2: delay
        }
    }
}

struct SplitDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let spacing: CGFloat = 4
                
                // Left Window (Win 1)
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win1).opacity(0.4)
                    .frame(width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3, height: h)
                    .position(x: phase == 1 ? (w - spacing) / 4 : (w - 2 * spacing) / 6, y: h / 2)
                
                // Container for Win 2 and Win 3
                Group {
                    // Win 2 (Top in split)
                    RoundedRectangle(cornerRadius: 4).fill(DemoColors.win2).opacity(0.4)
                        .frame(
                            width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3,
                            height: phase == 1 ? (h - spacing) / 2 : h
                        )
                        .position(
                            x: phase == 1 ? 3 * (w - spacing) / 4 + spacing : (w - 2 * spacing) / 2 + spacing,
                            y: phase == 1 ? (h - spacing) / 4 : h / 2
                        )
                    
                    // Win 3 (Bottom in split, Focused)
                    RoundedRectangle(cornerRadius: 4).fill(DemoColors.win3)
                        .frame(
                            width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3,
                            height: phase == 1 ? (h - spacing) / 2 : h
                        )
                        .position(
                            x: phase == 1 ? 3 * (w - spacing) / 4 + spacing : 5 * (w - 2 * spacing) / 6 + 2 * spacing,
                            y: phase == 1 ? 3 * (h - spacing) / 4 + spacing : h / 2
                        )
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3 // 0: side-by-side, 1: stacked, 2: delay
        }
    }
}

struct CompassPad<Demo: View>: View {
    @ObservedObject var model: ShortcutSettingsModel
    let title: String
    let prefix: String
    let demo: Demo

    init(model: ShortcutSettingsModel, title: String, prefix: String, @ViewBuilder demo: () -> Demo) {
        self.model = model
        self.title = title
        self.prefix = prefix
        self.demo = demo()
    }

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                recorderCell(for: "\(prefix)-up", label: "Up")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                recorderCell(for: "\(prefix)-left", label: "Left")
                demo
                    .frame(width: 120, height: 80)
                recorderCell(for: "\(prefix)-right", label: "Right")
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                recorderCell(for: "\(prefix)-down", label: "Down")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func recorderCell(for id: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ShortcutRecorderView(
                shortcut: .init(get: { model.shortcutValue(for: id) },
                                set: { model.setShortcutValue($0, for: id) }),
                onChange: { _ in }
            )
            .frame(width: 120, height: 22)
        }
    }
}

struct SnapGridPad: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                recorderCell(for: "snap-top-left", label: "Top Left")
                recorderCell(for: "snap-top-half", label: "Top")
                recorderCell(for: "snap-top-right", label: "Top Right")
            }
            GridRow {
                recorderCell(for: "snap-left-half", label: "Left")
                recorderCell(for: "snap-maximize", label: "Full")
                recorderCell(for: "snap-right-half", label: "Right")
            }
            GridRow {
                recorderCell(for: "snap-bottom-left", label: "Bottom Left")
                recorderCell(for: "snap-bottom-half", label: "Bottom")
                recorderCell(for: "snap-bottom-right", label: "Bottom Right")
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func recorderCell(for id: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ShortcutRecorderView(
                shortcut: .init(get: { model.shortcutValue(for: id) },
                                set: { model.setShortcutValue($0, for: id) }),
                onChange: { _ in }
            )
            .frame(width: 120, height: 22)
        }
    }
}

struct WorkspaceShortcutSectionView: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                WorkspacePatternCard(model: model, kind: .switchTo)
                WorkspacePatternCard(model: model, kind: .moveTo)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Overrides")
                    .font(.headline)
                Text("Individual workspace shortcuts override the global pattern above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(model.workspaceNumbers.indices, id: \.self) { index in
                        let workspaceName = model.workspaceNumbers[index]
                        WorkspaceOverrideRow(model: model, workspaceName: workspaceName)
                        if index < model.workspaceNumbers.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }
}

struct WorkspacePatternCard: View {
    @ObservedObject var model: ShortcutSettingsModel
    let kind: ShortcutSettingsModel.WorkspaceShortcutKind

    private let modifiers: [(String, NSEvent.ModifierFlags)] = [
        ("Control", .control),
        ("Option", .option),
        ("Command", .command),
        ("Shift", .shift),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.title)
                .font(.headline)
            Text(kind.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(modifiers, id: \.0) { label, modifier in
                    Toggle(
                        label,
                        isOn: Binding(
                            get: { model.workspacePatternIncludesModifier(modifier, kind: kind) },
                            set: { model.setWorkspacePatternModifier(modifier, enabled: $0, kind: kind) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }

            Divider()

            HStack {
                Text("Preview")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.workspacePatternDisplay(for: kind))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

struct WorkspaceOverrideRow: View {
    @ObservedObject var model: ShortcutSettingsModel
    let workspaceName: String

    var body: some View {
        HStack(spacing: 16) {
            Text("Workspace \(workspaceName)")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 100, alignment: .leading)

            WorkspaceOverrideField(model: model, workspaceName: workspaceName, kind: .switchTo)
            WorkspaceOverrideField(model: model, workspaceName: workspaceName, kind: .moveTo)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

struct WorkspaceOverrideField: View {
    @ObservedObject var model: ShortcutSettingsModel
    let workspaceName: String
    let kind: ShortcutSettingsModel.WorkspaceShortcutKind

    var body: some View {
        HStack(spacing: 8) {
            Text(kind == .switchTo ? "Switch:" : "Move:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            ShortcutRecorderView(
                shortcut: Binding(
                    get: { model.workspaceOverrideShortcutValue(workspaceName: workspaceName, kind: kind) },
                    set: { model.setWorkspaceOverrideShortcutValue($0, workspaceName: workspaceName, kind: kind) }
                ),
                onChange: { _ in }
            )
            .frame(width: 120, height: 22)
            
            if model.workspaceOverrideShortcutValue(workspaceName: workspaceName, kind: kind) == nil {
                Text(model.workspaceEffectiveNotation(for: workspaceName, kind: kind).map(displayBindingNotation) ?? "None")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutRow: View {
    @ObservedObject var model: ShortcutSettingsModel
    let action: ShortcutSettingsModel.Action

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderView(
                shortcut: .init(get: { model.shortcutValue(for: action.id) },
                                set: { model.setShortcutValue($0, for: action.id) }),
                onChange: { _ in }
            )
            .frame(width: 140, height: 22)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

struct ShortcutGeneralView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var enableWindowManagement = config.enableWindowManagement
    @State private var displayStyle = ExperimentalUISettings().displayStyle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GeneralSection(title: "Management") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Manage Windows")
                            Spacer()
                            Toggle("", isOn: $enableWindowManagement)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .onChange(of: enableWindowManagement) { newValue in
                                    toggleManageWindows(enabled: newValue)
                                }
                        }
                        
                        Text("Manage windows should be turned on. Manage windows turned off is experimental, in beta, and is not supported.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                GeneralSection(title: "Appearance") {
                    HStack {
                        Text("Menu bar style")
                        Spacer()
                        Picker("", selection: $displayStyle) {
                            ForEach(MenuBarStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .onChange(of: displayStyle) { newValue in
                            var settings = ExperimentalUISettings()
                            settings.displayStyle = newValue
                            TrayMenuModel.shared.experimentalUISettings = settings
                            updateTrayText()
                        }
                    }
                }

                GeneralSection(title: "Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button("Open Config File") { openConfigAction() }
                            Button("Reload Config") { reloadConfigAction() }
                        }
                        
                        Text("Shortcuts are edited here. Advanced configuration remains in `winmux.toml`.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private func toggleManageWindows(enabled: Bool) {
        Task { @MainActor in
            do {
                let targetUrl = try persistWindowManagementPreference(enabled: enabled)
                _ = try await reloadConfig(forceConfigUrl: targetUrl)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func openConfigAction() {
        switch findCustomConfigUrl() {
            case .file(let url):
                NSWorkspace.shared.open(url)
            case .noCustomConfigExists:
                let createdUrl = try? ensureBootstrapConfigExistsIfNeeded()
                NSWorkspace.shared.open(createdUrl ?? preferredEditableConfigUrl())
            case .ambiguousConfigError:
                NSWorkspace.shared.open(preferredEditableConfigUrl())
        }
    }

    private func reloadConfigAction() {
        Task {
            if let token: RunSessionGuard = .isServerEnabled {
                try await runLightSession(.menuBarButton, token) {
                    _ = try await reloadConfig()
                }
            }
        }
    }
}

struct GeneralSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            VStack(spacing: 0) {
                content
                    .padding(14)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
        }
    }
}

struct ShortcutAdvancedView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var configText = ""
    @State private var validationMessage: String? = nil
    @State private var saveMessage: String? = nil
    @State private var targetUrl: URL? = nil
    @State private var hasLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Config Editor")
                        .font(.headline)
                    if let targetUrl {
                        Text(targetUrl.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                Button("Reload From Disk") {
                    loadFromDisk()
                }
                Button("Validate") {
                    validateConfig()
                }
                Button("Save") {
                    saveConfig()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            } else if let saveMessage {
                Text(saveMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }

            TextEditor(text: $configText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
        }
        .padding(24)
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            loadFromDisk()
        }
    }

    private func loadFromDisk() {
        let resolvedUrl = advancedConfigEditorTargetUrl()
        targetUrl = resolvedUrl
        validationMessage = nil
        saveMessage = nil
        configText = advancedConfigEditorCurrentText(for: resolvedUrl)
    }

    private func validateConfig() {
        saveMessage = nil
        let parsed = parseConfig(configText)
        if parsed.errors.isEmpty {
            validationMessage = nil
            saveMessage = "Config is valid."
        } else {
            validationMessage = parsed.errors.map(\.description).joined(separator: "\n\n")
        }
    }

    private func saveConfig() {
        model.errorMessage = nil
        saveMessage = nil
        let parsed = parseConfig(configText)
        if !parsed.errors.isEmpty {
            validationMessage = parsed.errors.map(\.description).joined(separator: "\n\n")
            return
        }
        validationMessage = nil
        let resolvedUrl = targetUrl ?? advancedConfigEditorTargetUrl()
        targetUrl = resolvedUrl

        Task { @MainActor in
            do {
                let parentUrl = resolvedUrl.deletingLastPathComponent()
                if parentUrl.path != resolvedUrl.path {
                    try FileManager.default.createDirectory(at: parentUrl, withIntermediateDirectories: true)
                }
                try configText.write(to: resolvedUrl, atomically: true, encoding: .utf8)
                let isOk = try await reloadConfig(forceConfigUrl: resolvedUrl)
                if isOk {
                    saveMessage = "Saved and reloaded."
                    model.reload()
                } else {
                    saveMessage = nil
                    validationMessage = "Saved, but reload failed. Check the parser error message window."
                }
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
private func advancedConfigEditorTargetUrl() -> URL {
    preferredEditableConfigUrl()
}

@MainActor
private func advancedConfigEditorCurrentText(for targetUrl: URL) -> String {
    if let text = try? String(contentsOf: targetUrl, encoding: .utf8) {
        return text
    }
    return starterConfigText()
}

struct OpenShortcutSettingsButton: View {
    @Environment(\.openWindow) private var openWindow: OpenWindowAction

    var body: some View {
        Button("Settings…") {
            openShortcutSettingsWindow(openWindow)
        }
    }
}

@MainActor
private func shortcutSettingsWindow() -> NSWindow? {
    NSApplication.shared.windows.first { $0.identifier?.rawValue == shortcutSettingsWindowId }
}

@MainActor
private func presentShortcutSettingsWindow(_ window: NSWindow) {
    NSApp.activate(ignoringOtherApps: true)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}
