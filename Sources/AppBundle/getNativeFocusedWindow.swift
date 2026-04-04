import AppKit
import Common

@MainActor
var appForTests: (any AbstractApp)? = nil

@MainActor
private var focusedApp: (any AbstractApp)? {
    get async throws {
        if isUnitTest {
            return appForTests
        } else {
            check(appForTests == nil)
            return try await NSWorkspace.shared.frontmostApplication.flatMapAsync { @MainActor @Sendable in
                try await MacApp.getOrRegister($0)
            }
        }
    }
}

@MainActor
func getNativeFocusedWindow() async throws -> Window? {
    try await focusedApp?.getFocusedWindow()
}

@MainActor
func isNativeFocusOnUnmanagedMonitor() async throws -> Bool {
    guard let app = try await focusedApp else { return false }
    guard let macApp = app as? MacApp else { return false }
    return try await macApp.hasFocusedWindowOnUnmanagedMonitor()
}
