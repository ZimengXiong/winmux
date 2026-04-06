@testable import AppBundle
import XCTest

final class MouseDragSubjectTest: XCTestCase {
    func testShouldPromoteWindowDragToTabGroupDrag() {
        XCTAssertTrue(shouldPromoteWindowDragToTabGroupDrag(isOptionPressed: true, isTabbedWindow: true))
        XCTAssertFalse(shouldPromoteWindowDragToTabGroupDrag(isOptionPressed: false, isTabbedWindow: true))
        XCTAssertFalse(shouldPromoteWindowDragToTabGroupDrag(isOptionPressed: true, isTabbedWindow: false))
    }

    func testSameWorkspaceSurfaceIntentRulesInUnmanagedMode() {
        XCTAssertTrue(shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: false,
            subject: .window,
            detachOrigin: .window,
            isOptionPressed: true,
        ))
        XCTAssertFalse(shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: false,
            subject: .window,
            detachOrigin: .window,
            isOptionPressed: false,
        ))
        XCTAssertTrue(shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: false,
            subject: .window,
            detachOrigin: .tabStrip,
            isOptionPressed: false,
        ))
        XCTAssertFalse(shouldAllowSameWorkspaceWindowSurfaceIntent(
            enableWindowManagement: false,
            subject: .group,
            detachOrigin: .window,
            isOptionPressed: true,
        ))
    }
}
