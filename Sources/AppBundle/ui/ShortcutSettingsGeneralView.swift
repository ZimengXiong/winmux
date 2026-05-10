import AppKit
import Common
import MASShortcut
import SwiftUI

struct ShortcutGeneralView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var enableWindowManagement = config.enableWindowManagement
    @State private var displayStyle = ExperimentalUISettings().displayStyle
    @State private var workspaceSidebarMenuBarReserveHeight = config.workspaceSidebar.menuBarReserveHeight
    @State private var projectDeletionAction = config.workspaceSidebar.projectDeletionAction

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

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Deleting projects")
                                Text("Close windows keeps app confirmation dialogs visible and aborts deletion if a window stays open.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Picker("", selection: $projectDeletionAction) {
                                ForEach(WorkspaceProjectDeletionAction.allCases) { action in
                                    Text(action.settingsTitle).tag(action)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 210)
                            .onChange(of: projectDeletionAction) { newValue in
                                setProjectDeletionAction(newValue)
                            }
                        }
                    }
                }

                GeneralSection(title: "Appearance") {
                    VStack(alignment: .leading, spacing: 14) {
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

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sidebar menu bar space")
                                Text("Use 0 px when the macOS menu bar auto-hides.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(workspaceSidebarMenuBarReserveHeight) px")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                            Stepper(
                                "",
                                value: $workspaceSidebarMenuBarReserveHeight,
                                in: 0 ... 72,
                                step: 1,
                            )
                            .labelsHidden()
                            .onChange(of: workspaceSidebarMenuBarReserveHeight) { newValue in
                                setWorkspaceSidebarMenuBarReserveHeight(newValue)
                            }
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

    private func setWorkspaceSidebarMenuBarReserveHeight(_ height: Int) {
        Task { @MainActor in
            do {
                let targetUrl = try persistWorkspaceSidebarMenuBarReserveHeight(height)
                _ = try await reloadConfig(forceConfigUrl: targetUrl)
                WorkspaceSidebarPanel.shared.refresh()
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func setProjectDeletionAction(_ action: WorkspaceProjectDeletionAction) {
        Task { @MainActor in
            do {
                let targetUrl = try persistWorkspaceSidebarProjectDeletionAction(action)
                _ = try await reloadConfig(forceConfigUrl: targetUrl)
                projectDeletionAction = config.workspaceSidebar.projectDeletionAction
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
                    let isOk = try await reloadConfig()
                    if isOk {
                        workspaceSidebarMenuBarReserveHeight = config.workspaceSidebar.menuBarReserveHeight
                        projectDeletionAction = config.workspaceSidebar.projectDeletionAction
                        model.reload()
                    }
                }
            }
        }
    }
}

private extension WorkspaceProjectDeletionAction {
    var settingsTitle: String {
        switch self {
            case .closeWindows:
                "Close project windows"
            case .moveWindowsToFallback:
                "Move windows elsewhere"
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
