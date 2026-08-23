import AppKit
import Common
import XCTest

/// Hidden (corner-parked) windows are re-asserted only when macOS could have moved windows
/// behind our back with no AX events delivered. Every other event must leave parked windows
/// alone — re-asserting them costs one AX round-trip per hidden window per event.
final class RefreshSessionEventReassertionTest: XCTestCase {
    func testOnlyWakeAndStartupRequireHiddenWindowsReassertion() {
        XCTAssertTrue(RefreshSessionEvent.startup.requiresHiddenWindowsReassertion)
        XCTAssertTrue(
            RefreshSessionEvent.globalObserver(NSWorkspace.didWakeNotification.rawValue)
                .requiresHiddenWindowsReassertion
        )
        XCTAssertTrue(
            RefreshSessionEvent.globalObserver(NSWorkspace.screensDidWakeNotification.rawValue)
                .requiresHiddenWindowsReassertion
        )

        XCTAssertFalse(RefreshSessionEvent.ax(kAXMovedNotification as String).requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.ax(kAXResizedNotification as String).requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.ax(kAXWindowCreatedNotification as String).requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.ax(kAXUIElementDestroyedNotification as String).requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.globalObserverLeftMouseUp.requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.resetManipulatedWithMouse.requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.hotkeyBinding.requiresHiddenWindowsReassertion)
        XCTAssertFalse(RefreshSessionEvent.configAutoReload.requiresHiddenWindowsReassertion)
        XCTAssertFalse(
            RefreshSessionEvent.globalObserver(NSWorkspace.didActivateApplicationNotification.rawValue)
                .requiresHiddenWindowsReassertion
        )
    }
}
