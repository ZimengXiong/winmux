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

    var iconAppearance: MenuBarIconAppearance {
        get {
            guard let value = UserDefaults.standard.string(forKey: ExperimentalUISettingsItems.iconAppearance.rawValue) else {
                return .color
            }
            return MenuBarIconAppearance(rawValue: value) ?? .color
        }
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: ExperimentalUISettingsItems.iconAppearance.rawValue)
            UserDefaults.standard.synchronize()
        }
    }
}

enum MenuBarIconAppearance: String, CaseIterable, Identifiable, Equatable, Hashable {
    case color
    case monochrome

    var id: String { rawValue }

    var title: String {
        switch self {
            case .color: "Color"
            case .monochrome: "Monochrome"
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
    case iconAppearance
}
