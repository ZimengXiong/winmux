import Sparkle

/// Coordinates application updates from the release appcast.
@MainActor
public enum AutomaticUpdates {
    private static let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil,
    )

    /// Starts Sparkle's periodic update checks for the main application bundle.
    public static func start() {
        _ = updaterController
    }

    /// Displays Sparkle's standard update-checking interface.
    public static func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
