import AppKit
import DeckCore
import SwiftUI

struct DeckSettingsView: View {
    private let storage = DeckStorage()

    @State private var profiles: [DeckProfileSummary] = []
    @State private var selectedProfileName: String?
    @State private var selectedProfileUrl: URL?
    @State private var profileText = ""
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var newProfileName = ""
    @State private var newProfileRoot = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Project Templates")
                        .font(.headline)
                    Spacer()
                    Button {
                        reloadProfiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload profiles")
                }

                List(selection: $selectedProfileName) {
                    ForEach(profiles, id: \.name) { profile in
                        Text(profile.name)
                            .tag(Optional(profile.name))
                    }
                }
                .frame(minWidth: 180)
                .onChange(of: selectedProfileName) { _ in
                    loadSelectedProfile()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    TextField("New template name", text: $newProfileName)
                    TextField("Project root", text: $newProfileRoot)
                    HStack {
                        Button("Create") {
                            createProfile()
                        }
                        Button("Open Folder") {
                            openProfilesFolder()
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 260)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedProfileName ?? "Project Template")
                            .font(.headline)
                        Text(selectedProfileUrl?.path ?? storage.profilesDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Validate") {
                        validateProfile()
                    }
                    .disabled(selectedProfileUrl == nil)
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(selectedProfileUrl == nil)
                }

                if let errorMessage {
                    messageText(errorMessage, color: .red)
                } else if let message {
                    messageText(message, color: .secondary)
                }

                TextEditor(text: $profileText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
            }
            .padding(24)
        }
        .task {
            reloadProfiles()
        }
    }

    private func messageText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .padding(.horizontal, 2)
            .textSelection(.enabled)
    }

    private func reloadProfiles() {
        do {
            profiles = try storage.listProfiles()
            if selectedProfileName == nil || !profiles.contains(where: { $0.name == selectedProfileName }) {
                selectedProfileName = profiles.first?.name
            }
            loadSelectedProfile()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSelectedProfile() {
        guard let selectedProfileName,
              let summary = profiles.first(where: { $0.name == selectedProfileName })
        else {
            selectedProfileUrl = nil
            profileText = ""
            return
        }
        selectedProfileUrl = summary.url
        profileText = (try? String(contentsOf: summary.url, encoding: .utf8)) ?? ""
        message = nil
        errorMessage = nil
    }

    private func validateProfile() {
        do {
            _ = try DeckProfileParser.parse(profileText, sourceName: selectedProfileName)
            message = "Profile is valid."
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
            message = nil
        }
    }

    private func saveProfile() {
        guard let selectedProfileUrl else { return }
        do {
            _ = try DeckProfileParser.parse(profileText, sourceName: selectedProfileName)
            try profileText.write(to: selectedProfileUrl, atomically: true, encoding: .utf8)
            errorMessage = nil
            reloadProfiles()
            message = "Saved."
        } catch {
            errorMessage = String(describing: error)
            message = nil
        }
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "New template name is required."
            return
        }
        do {
            let root = newProfileRoot.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = try storage.createStarterProfile(name: name, root: root.isEmpty ? nil : root)
            newProfileName = ""
            newProfileRoot = ""
            reloadProfiles()
            selectedProfileName = url.deletingPathExtension().lastPathComponent
            loadSelectedProfile()
            message = "Created \(url.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
            message = nil
        }
    }

    private func openProfilesFolder() {
        try? storage.ensureDirectories()
        NSWorkspace.shared.open(storage.profilesDirectory)
    }
}
