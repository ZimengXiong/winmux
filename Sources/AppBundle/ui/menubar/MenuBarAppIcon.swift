import SwiftUI

/// A compact rendering of the windows in the app icon.
struct MenuBarAppIcon: View {
    @EnvironmentObject private var viewModel: TrayMenuModel

    var body: some View {
        Image(viewModel.experimentalUISettings.iconAppearance == .color ? "MenuBarIcon" : "MenuBarIconMonochrome")
            .renderingMode(viewModel.experimentalUISettings.iconAppearance == .color ? .original : .template)
            .accessibilityLabel("WinMux")
    }
}
