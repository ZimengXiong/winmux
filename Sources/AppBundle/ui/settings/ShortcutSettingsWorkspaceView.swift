import AppKit
import Common
import MASShortcut
import SwiftUI

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

