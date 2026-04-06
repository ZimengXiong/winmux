import SwiftUI

struct ExperimentalUISettings {
    var displayStyle: MenuBarStyle {
        get {
            if let value = UserDefaults.standard.string(forKey: ExperimentalUISettingsItems.displayStyle.rawValue) {
                return MenuBarStyle(rawValue: value) ?? .monospacedText
            } else {
                return .monospacedText
            }
        }
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: ExperimentalUISettingsItems.displayStyle.rawValue)
            UserDefaults.standard.synchronize()
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable, Equatable, Hashable {
    case monospacedText
    case systemText
    case squares
    case i3
    case i3Ordered
    var id: String { rawValue }
    var title: String {
        switch self {
            case .monospacedText: "Monospaced font"
            case .systemText: "System font"
            case .squares: "Square images"
            case .i3: "i3 style grouped"
            case .i3Ordered: "i3 style ordered"
        }
    }
}

enum ExperimentalUISettingsItems: String {
    case displayStyle
}

@MainActor
func getExperimentalUISettingsMenu(viewModel: TrayMenuModel) -> some View {
    let color = AppearanceTheme.current == .dark ? Color.white : Color.black
    return Menu {
        Picker("Menu bar style", selection: Binding(
            get: { viewModel.experimentalUISettings.displayStyle },
            set: { viewModel.experimentalUISettings.displayStyle = $0 }
        )) {
            ForEach(MenuBarStyle.allCases) { style in
                HStack {
                    MenuBarLabel(style: style, color: color)
                        .environmentObject(viewModel)
                    Text(style.title)
                }
                .tag(style)
            }
        }
        .pickerStyle(.inline)
    } label: {
        Text("Experimental UI Settings")
    }
}
