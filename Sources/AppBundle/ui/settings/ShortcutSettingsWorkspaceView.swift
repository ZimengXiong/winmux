import AppKit
import Common
import MASShortcut
import SwiftUI

struct WorkspaceShortcutSectionView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var showsOverrides = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkspacePatternRow(model: model, kind: .switchTo)
            Divider()
            WorkspacePatternRow(model: model, kind: .moveTo)
            Divider()
            DisclosureGroup("Custom overrides", isExpanded: $showsOverrides) {
                Text("Use an override only when a workspace needs a different shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                WorkspaceOverridesGrid(model: model)
                    .padding(.top, 8)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(.vertical, 4)
    }
}

private struct WorkspacePatternRow: View {
    @ObservedObject var model: ShortcutSettingsModel
    let kind: ShortcutSettingsModel.WorkspaceShortcutKind

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kind == .switchTo ? "Switch workspaces" : "Move window to workspace")
                Text(kind.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            WorkspaceModifierMenu(model: model, kind: kind)
            Text(model.workspacePatternDisplay(for: kind))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 74, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct WorkspaceModifierMenu: View {
    @ObservedObject var model: ShortcutSettingsModel
    let kind: ShortcutSettingsModel.WorkspaceShortcutKind

    private let modifiers: [(String, NSEvent.ModifierFlags)] = [
        ("Control", .control),
        ("Option", .option),
        ("Command", .command),
        ("Shift", .shift),
    ]

    var body: some View {
        Menu {
            ForEach(modifiers, id: \.0) { label, modifier in
                Toggle(label, isOn: Binding(
                    get: { model.workspacePatternIncludesModifier(modifier, kind: kind) },
                    set: { model.setWorkspacePatternModifier(modifier, enabled: $0, kind: kind) }
                ))
            }
        } label: {
            Text("Modifiers")
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .frame(width: 94)
    }
}

private struct WorkspaceOverridesGrid: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Workspace").foregroundStyle(.secondary)
                Text("Switch").foregroundStyle(.secondary)
                Text("Move").foregroundStyle(.secondary)
            }
            .font(.caption)

            ForEach(model.workspaceNumbers, id: \.self) { workspaceName in
                GridRow {
                    Text(workspaceName)
                        .frame(width: 78, alignment: .leading)
                    WorkspaceOverrideRecorder(model: model, workspaceName: workspaceName, kind: .switchTo)
                    WorkspaceOverrideRecorder(model: model, workspaceName: workspaceName, kind: .moveTo)
                }
            }
        }
    }
}

private struct WorkspaceOverrideRecorder: View {
    @ObservedObject var model: ShortcutSettingsModel
    let workspaceName: String
    let kind: ShortcutSettingsModel.WorkspaceShortcutKind

    var body: some View {
        ShortcutRecorderView(
            shortcut: Binding(
                get: { model.workspaceOverrideShortcutValue(workspaceName: workspaceName, kind: kind) },
                set: { model.setWorkspaceOverrideShortcutValue($0, workspaceName: workspaceName, kind: kind) }
            ),
            onChange: { _ in }
        )
        .frame(width: 150, height: 22)
    }
}
