@testable import AppBundle
import Combine
import XCTest

/// The tray model is republished wholesale on every refresh session, and each unguarded
/// @Published write re-renders every observing view (menu bar label, sidebar panels, tab
/// strips). setIfChanged must publish only on real changes.
final class TrayMenuModelSetIfChangedTest: XCTestCase {
    @MainActor
    func testSetIfChangedPublishesOnlyOnRealChanges() {
        let model = TrayMenuModel()
        var publishCount = 0
        let subscription = model.objectWillChange.sink { publishCount += 1 }
        defer { subscription.cancel() }

        model.setIfChanged(\.trayText, "A")
        XCTAssertEqual(publishCount, 1)

        // Same value again: no publish, no view invalidation.
        model.setIfChanged(\.trayText, "A")
        model.setIfChanged(\.trayText, "A")
        XCTAssertEqual(publishCount, 1)

        model.setIfChanged(\.trayText, "B")
        XCTAssertEqual(publishCount, 2)

        model.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, nil)
        XCTAssertEqual(publishCount, 2, "writing the default value must not publish")

        model.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, "ws")
        XCTAssertEqual(publishCount, 3)
    }
}
