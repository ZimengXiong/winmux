@testable import AppBundle
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

    /// A wake event that is waiting behind an in-flight session must survive coalescing with the
    /// activeSpaceDidChange / leftMouseUp events that routinely follow a wake, otherwise the only
    /// pass that re-parks drifted hidden windows is silently dropped.
    @MainActor
    func testCoalescingKeepsWakeOverEqualWeightEvents() async throws {
        let wake = RefreshSessionEvent.globalObserver(NSWorkspace.didWakeNotification.rawValue)
        let spaceChanged = RefreshSessionEvent.globalObserver(NSWorkspace.activeSpaceDidChangeNotification.rawValue)

        var delivered: [String] = []
        setScheduledRefreshOverrideForTests { event, _ in delivered.append(event.description) }
        defer { setScheduledRefreshOverrideForTests(nil) }

        // scheduleRefreshSession assigns activeRefreshTask synchronously, so the two events that
        // follow land in pendingRefreshRequest and merge there.
        scheduleRefreshSession(.hotkeyBinding)
        scheduleRefreshSession(wake)
        scheduleRefreshSession(spaceChanged)
        try await waitForScheduledRefreshForTests()

        XCTAssertEqual(delivered, [RefreshSessionEvent.hotkeyBinding.description, wake.description])
    }

    /// A wake session that is already running, rather than pending, is cancelled outright by the
    /// next light session. Its reassertion requirement must be re-queued: nothing else will ever
    /// ask for hidden windows to be re-parked, so dropping it strands them until the next sleep.
    @MainActor
    func testLightSessionPreemptionKeepsWakeReassertion() async throws {
        let wake = RefreshSessionEvent.globalObserver(NSWorkspace.didWakeNotification.rawValue)

        var delivered: [String] = []
        let gate = AwaitableOneTimeBroadcastLatch()
        setScheduledRefreshOverrideForTests { event, _ in
            delivered.append(event.description)
            if delivered.count == 1 { try await gate.await() } // keep the wake session in flight
        }
        defer { setScheduledRefreshOverrideForTests(nil) }

        scheduleRefreshSession(wake)
        await Task.yield() // let the wake session start and park on the gate
        _ = try await runLightSession(.hotkeyBinding, .forceRun) {} // cancels it mid-flight
        await gate.signalToAll()
        try await waitForScheduledRefreshForTests()

        // The wake is delivered once when its session starts and must be delivered a second time
        // after the light session re-queues it. Exactly one delivery means it was dropped.
        let wakeDeliveries = delivered.filter { $0 == wake.description }.count
        XCTAssertEqual(wakeDeliveries, 2, "wake reassertion was not re-queued after pre-emption: \(delivered)")
    }
}