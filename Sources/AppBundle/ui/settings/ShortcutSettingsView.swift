import AppKit
import Common
import MASShortcut
import SwiftUI

public let shortcutSettingsWindowId = "\(winMuxAppName).shortcutSettings"

@MainActor
public func getShortcutSettingsWindow(model: ShortcutSettingsModel) -> some Scene {
    SwiftUI.Window("WinMux Settings", id: shortcutSettingsWindowId) {
        ShortcutSettingsView(model: model)
            .frame(minWidth: 760, minHeight: 620)
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
    case shortcuts
    case workspaces
    case behavior
    case appearance
    case automation
    case configuration

    var id: Self { self }

    var label: String {
        switch self {
            case .shortcuts: "Shortcuts"
            case .workspaces: "Workspaces"
            case .behavior: "Behavior"
            case .appearance: "Appearance"
            case .automation: "Automation & Rules"
            case .configuration: "Configuration"
        }
    }

    var icon: String {
        switch self {
            case .shortcuts: "keyboard"
            case .workspaces: "rectangle.3.group"
            case .behavior: "arrow.triangle.2.circlepath"
            case .appearance: "sidebar.left"
            case .automation: "flowchart"
            case .configuration: "doc.text"
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var selectedItem: SettingsSidebarItem? = .shortcuts

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                ForEach([SettingsSidebarItem.shortcuts, .workspaces, .behavior, .appearance, .automation, .configuration]) { item in
                    NavigationLink(value: item) {
                        Label(item.label, systemImage: item.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch selectedItem {
                    case .shortcuts:
                        ShortcutSettingsShortcutsView(model: model)
                    case .workspaces:
                        ShortcutSettingsWorkspacePane(model: model)
                    case .behavior:
                        ShortcutBehaviorSettingsView(model: model)
                    case .appearance:
                        ShortcutAppearanceSettingsView(model: model)
                    case .automation:
                        ShortcutAutomationSettingsView(model: model)
                    case .configuration:
                        ShortcutAdvancedView(model: model)
                    case nil:
                        Text("Select an item")
                }
            }
            .navigationTitle(selectedItem?.label ?? "")
        }
    }
}

struct ShortcutSettingsShortcutsView: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        ShortcutCategoryView(model: model, category: .managed)
    }
}

struct ShortcutSettingsWorkspacePane: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        ShortcutCategoryView(model: model, category: .common)
    }
}

struct ShortcutCategoryView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let category: ShortcutSettingsModel.Category

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
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
            .padding(20)
        }
    }
}

struct ShortcutSectionView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let section: ShortcutSettingsModel.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
