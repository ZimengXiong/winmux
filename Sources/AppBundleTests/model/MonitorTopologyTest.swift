@testable import AppBundle
import AppKit
import Common
import XCTest

private struct MonitorTopologyTestMonitor: Monitor {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

@MainActor
final class MonitorTopologyTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSortedMonitorsUseSpatialOrderEvenWhenMainDisplayIsOnTheRight() {
        let left = MonitorTopologyTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Left",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        let main = MonitorTopologyTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        setMonitorsForTests([main, left])

        XCTAssertEqual(sortedMonitors.map(\.name), ["Left", "Main"])
        XCTAssertEqual(sortedMonitors.map(\.monitorId_oneBased), [1, 2])
        XCTAssertEqual(sortedMonitors.map(\.monitorAppKitNsScreenScreensId), [2, 1])
        XCTAssertEqual(MonitorDescription.sequenceNumber(1).resolveMonitor(sortedMonitors: sortedMonitors)?.name, "Left")
        XCTAssertEqual(MonitorDescription.main.resolveMonitor(sortedMonitors: sortedMonitors)?.name, "Main")
        XCTAssertEqual(left.findRelativeMonitor(inDirection: .right)?.monitorsInDirection.map(\.name), ["Left", "Main"])
    }

    func testWorkspaceSidebarInsetAppliesOnlyToPanelMonitor() {
        let main = MonitorTopologyTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = MonitorTopologyTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        config.workspaceSidebar.enabled = true
        config.workspaceSidebar.collapsedWidth = 54
        config.workspaceSidebar.monitor = [.main]
        config.gaps = .zero

        XCTAssertEqual(main.visibleRectPaddedByOuterGaps.topLeftX, 54)
        XCTAssertEqual(main.visibleRectPaddedByOuterGaps.width, 1866)
        XCTAssertEqual(secondary.visibleRectPaddedByOuterGaps.topLeftX, 1920)
        XCTAssertEqual(secondary.visibleRectPaddedByOuterGaps.width, 1920)
    }
}
