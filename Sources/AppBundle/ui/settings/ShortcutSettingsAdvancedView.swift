import AppKit
import Common
import MASShortcut
import SwiftUI

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
func shortcutSettingsWindow() -> NSWindow? {
    NSApplication.shared.windows.first { $0.identifier?.rawValue == shortcutSettingsWindowId }
}

@MainActor
func presentShortcutSettingsWindow(_ window: NSWindow) {
    NSApp.activate(ignoringOtherApps: true)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}
