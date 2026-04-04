@testable import AppBundle
import AppKit
import XCTest

final class RefreshFocusSyncTest: XCTestCase {
    @MainActor
    func testShouldNotSyncFocusBackToPopupWindow() {
        setUpWorkspacesForTests()

        let popup = TestWindow.new(id: 1, parent: macosPopupWindowsContainer)

        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: popup, frontmostActivationPolicy: .accessory))
    }

    @MainActor
    func testShouldNotSyncFocusBackToAccessoryAppWithoutFocusedWindow() {
        XCTAssertFalse(shouldSyncFocusBackToMacOs(nativeFocused: nil, frontmostActivationPolicy: .accessory))
    }

    @MainActor
    func testShouldNotSyncFocusBackWhenNativeFocusIsOnUnmanagedMonitor() {
        XCTAssertFalse(
            shouldSyncFocusBackToMacOs(
                nativeFocused: nil,
                frontmostActivationPolicy: .regular,
                nativeFocusIsOnUnmanagedMonitor: true,
            )
        )
    }

    @MainActor
    func testShouldSyncFocusBackToRegularWorkspaceWindow() {
        setUpWorkspacesForTests()

        let window = TestWindow.new(id: 1, parent: focus.workspace)

        XCTAssertTrue(shouldSyncFocusBackToMacOs(nativeFocused: window, frontmostActivationPolicy: .regular))
    }
}
