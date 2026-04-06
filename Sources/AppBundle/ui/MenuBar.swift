    import Common
    import Foundation
    import SwiftUI
    
private let winmuxRepositoryURL = "https://github.com/zimengxiong/winmux"
private let winmuxNewIssueURL = "https://github.com/zimengxiong/winmux/issues/new/choose"

    @MainActor
    public func menuBar(viewModel: TrayMenuModel) -> some Scene { // todo should it be converted to "SwiftUI struct"?
        MenuBarExtra {
            let shortIdentification = "\(winMuxAppName) v\(winMuxAppVersion) \(gitShortHash)"
            let identification      = "\(winMuxAppName) v\(winMuxAppVersion) \(gitHash)"
        Text(shortIdentification)
        Button("Copy to clipboard") { identification.copyToClipboard() }
            .keyboardShortcut("C", modifiers: .command)
        Divider()
        Button(viewModel.isEnabled ? "Disable" : "Enable") {
            Task {
                try await runLightSession(.menuBarButton, .forceRun) { () throws in
                    _ = try await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                        .run(.defaultEnv, .emptyStdin)
                }
            }
        }.keyboardShortcut("E", modifiers: .command)
        Toggle("Manage Windows", isOn: Binding(
            get: { config.enableWindowManagement },
            set: { enabled in setWindowManagementFromMenu(enabled) },
        ))
        OpenShortcutSettingsButton()
        openConfigButton()
        reloadConfigButton()
        Button("GitHub Repository") {
            openURLString(winmuxRepositoryURL)
        }
        Button("File an issue...") {
            openURLString(winmuxNewIssueURL)
        }
        Button("Quit \(winMuxAppName)") {
            Task {
                defer { terminateApp() }
                try await terminationHandler.beforeTermination()
            }
        }.keyboardShortcut("Q", modifiers: .command)
    } label: {
        if viewModel.isEnabled {
            MenuBarLabel().environmentObject(viewModel)
        } else {
            Image(systemName: "pause.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let button = Button("Open config") {
        switch findCustomConfigUrl() {
            case .file(let url):
                NSWorkspace.shared.open(url)
            case .noCustomConfigExists:
                let createdUrl = try? ensureBootstrapConfigExistsIfNeeded()
                NSWorkspace.shared.open(createdUrl ?? preferredEditableConfigUrl())
            case .ambiguousConfigError:
                NSWorkspace.shared.open(preferredEditableConfigUrl())
        }
    }.keyboardShortcut(",", modifiers: .command)
    if showShortcutGroup {
        shortcutGroup(label: Text("⌘ ,"), content: button)
    } else {
        button
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload config") {
            Task {
                try await runLightSession(.menuBarButton, token) { _ = try await reloadConfig() }
            }
        }.keyboardShortcut("R", modifiers: .command)
        if showShortcutGroup {
            shortcutGroup(label: Text("⌘ R"), content: button)
        } else {
            button
        }
    }
}

@MainActor
private func openURLString(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}

@MainActor
private func setWindowManagementFromMenu(_ enabled: Bool) {
    Task { @MainActor in
        do {
            try await runLightSession(.menuBarButton, .forceRun) {
                let targetUrl = try persistWindowManagementPreference(enabled: enabled)
                _ = try await reloadConfig(forceConfigUrl: targetUrl)
            }
        } catch {
            MessageModel.shared.message = Message(
                description: "Window Management Toggle Error",
                body: error.localizedDescription,
            )
        }
    }
}
