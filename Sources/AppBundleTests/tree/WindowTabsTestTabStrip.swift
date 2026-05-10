@testable import AppBundle
import AppKit
import CoreGraphics
import XCTest

@MainActor extension WindowTabsTest {
    func testUnmanagedCrossWorkspaceMoveHintStillWorks() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        let main = WindowTabsTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WindowTabsTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let previousValue = config.enableWindowManagement
        config.enableWindowManagement = false
        defer {
            config.enableWindowManagement = previousValue
            clearPendingWindowDragIntent()
        }

        let sourceWorkspace = Workspace.get(byName: "source")
        XCTAssertTrue(sourceWorkspace.focusWorkspace())
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 220, height: 180)

        let targetWorkspace = Workspace.get(byName: "target")
        targetWorkspace.seedMonitorIfNeeded(secondary)
        XCTAssertTrue(secondary.setActiveWorkspace(targetWorkspace))
        let mouseLocation = targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps.center

        XCTAssertTrue(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: mouseLocation,
            subject: .window,
            detachOrigin: .window,
        ))

        XCTAssertEqual(debugPendingWindowDragIntentSummary()?.kind, .moveToWorkspace(workspaceName: targetWorkspace.name))
    }

    @MainActor
    func testCrossWorkspaceDragOverTargetWindowOffersSurfaceIntent() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let sourceWorkspace = Workspace.get(byName: "source")
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 220, height: 180)

        let targetWorkspace = Workspace.get(byName: "target")
        let target = TestWindow.new(id: 2, parent: targetWorkspace.rootTilingContainer)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 120, topLeftY: 80, width: 420, height: 300)
        XCTAssertTrue(targetWorkspace.focusWorkspace())

        XCTAssertTrue(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: target.stackSplitDropZoneRect(position: .left).orDie().center,
            subject: .window,
            detachOrigin: .window,
        ))

        XCTAssertEqual(
            debugPendingWindowDragIntentSummary()?.kind,
            .stackSplit(targetWindowId: target.windowId, position: .left)
        )
    }

    @MainActor
    func testClearingMissingUnmanagedPreviewDoesNotHideManagedDragPreview() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        clearPendingUnmanagedWindowSnap()
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        root.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 220)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)
        let mouseLocation = target.tabDropInteractionRect.orDie().center

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))
        XCTAssertTrue(WindowTabDropPreviewPanel.shared.isVisible)

        clearPendingUnmanagedWindowSnap()

        XCTAssertTrue(WindowTabDropPreviewPanel.shared.isVisible)
        clearPendingWindowDragIntent()
    }

    @MainActor
    func testWindowTabStripGroupDragDefersToDetachedTabDrag() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertTrue(shouldDeferWindowTabStripGroupDragToDetachedTabDrag())
    }

    @MainActor
    func testWindowTabStripGroupDragEndIsIgnoredForDetachedTabDrags() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertFalse(shouldHandleWindowTabStripGroupDragEnd())
    }

    @MainActor
    func testWindowTabStripGroupDragEndRunsForGroupDrags() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertTrue(shouldHandleWindowTabStripGroupDragEnd())
    }

    func testWindowTabStripDragInProgressRecognizesDetachedTabDrag() {
        XCTAssertTrue(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
        ))
    }

    func testWindowTabStripDragInProgressRecognizesGroupDrag() {
        XCTAssertTrue(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: false,
        ))
    }

    func testWindowTabStripLayoutReservesGroupDragHandleGutters() {
        let stripWidth: CGFloat = 360
        let expectedTabsWidth = stripWidth
            - (windowTabStripReservedGroupHandleWidth() * 2)
            - (windowTabStripContentPadding() * 2)

        XCTAssertEqual(windowTabStripAvailableTabsWidth(stripWidth: stripWidth), expectedTabsWidth)
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: stripWidth, count: 1), 240)
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: stripWidth, count: 3), 240)
        XCTAssertLessThan(windowTabStripAvailableTabsWidth(stripWidth: stripWidth), stripWidth)
    }

    func testWindowTabStripLeadingFadeOnlyAppearsAfterScrollingFromLeftEdge() {
        let stripWidth: CGFloat = 240

        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: 0,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: -0.5,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: false,
            contentMinX: -12,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertGreaterThan(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: -2,
            stripWidth: stripWidth,
        ), 0)
    }

    func testWindowTabStripTrailingFadeTracksScrollableContent() {
        let stripWidth: CGFloat = 240

        XCTAssertEqual(windowTabTrailingScrollFadeWidth(isScrollable: false, stripWidth: stripWidth), 0)
        XCTAssertGreaterThan(windowTabTrailingScrollFadeWidth(isScrollable: true, stripWidth: stripWidth), 0)
    }

    func testWindowIntentPreviewSymbolsMatchIntentStyle() {
        XCTAssertEqual(windowIntentPreviewSymbolName(for: .tabInsert, isGroup: false), "square.stack.3d.up")
        XCTAssertEqual(windowIntentPreviewSymbolName(for: .detach, isGroup: false), "arrow.up.left.and.arrow.down.right")
        XCTAssertEqual(windowIntentPreviewSymbolName(for: .stackSplit, isGroup: false), "rectangle.split.2x1")
        XCTAssertEqual(windowIntentPreviewSymbolName(for: .swap, isGroup: false), "arrow.left.arrow.right")
        XCTAssertEqual(windowIntentPreviewSymbolName(for: .workspaceMove, isGroup: false), "macwindow.badge.plus")
        XCTAssertEqual(windowIntentPreviewSymbolName(for: .workspaceMove, isGroup: true), "rectangle.stack.badge.plus")
    }

    func testWindowIntentPreviewGuideLinesFollowIntentGeometry() {
        let size = CGSize(width: 120, height: 80)

        XCTAssertNil(windowIntentPreviewGuideLine(for: .rounded, in: size))
        XCTAssertEqual(
            windowIntentPreviewGuideLine(for: .splitLeft, in: size),
            WindowIntentPreviewGuideLine(start: CGPoint(x: 119, y: 8), end: CGPoint(x: 119, y: 72)),
        )
        XCTAssertEqual(
            windowIntentPreviewGuideLine(for: .splitBelow, in: size),
            WindowIntentPreviewGuideLine(start: CGPoint(x: 8, y: 1), end: CGPoint(x: 112, y: 1)),
        )
        XCTAssertEqual(
            windowIntentPreviewGuideLine(for: .tabStrip, in: size),
            WindowIntentPreviewGuideLine(start: CGPoint(x: 10, y: 79), end: CGPoint(x: 110, y: 79)),
        )
    }

    func testWindowIntentPreviewFillStaysGrayOverDarkContent() {
        let fill = WindowIntentPreviewPalette.fillColor.usingColorSpace(.deviceRGB).orDie()
        let matte = mattePanelNSColor.usingColorSpace(.deviceRGB).orDie()
        let darkContent: CGFloat = 0.05
        let lightContent: CGFloat = 1
        let darkRed = fill.alphaComponent * fill.redComponent + (1 - fill.alphaComponent) * darkContent
        let darkGreen = fill.alphaComponent * fill.greenComponent + (1 - fill.alphaComponent) * darkContent
        let darkBlue = fill.alphaComponent * fill.blueComponent + (1 - fill.alphaComponent) * darkContent
        let lightRed = fill.alphaComponent * fill.redComponent + (1 - fill.alphaComponent) * lightContent
        let lightGreen = fill.alphaComponent * fill.greenComponent + (1 - fill.alphaComponent) * lightContent
        let lightBlue = fill.alphaComponent * fill.blueComponent + (1 - fill.alphaComponent) * lightContent

        XCTAssertEqual(fill.redComponent, matte.redComponent, accuracy: 0.001)
        XCTAssertEqual(fill.greenComponent, matte.greenComponent, accuracy: 0.001)
        XCTAssertEqual(fill.blueComponent, matte.blueComponent, accuracy: 0.001)
        XCTAssertEqual(fill.alphaComponent, matte.alphaComponent, accuracy: 0.001)
        XCTAssertGreaterThan(fill.alphaComponent, 0.88)
        XCTAssertGreaterThan(min(darkRed, darkGreen, darkBlue), 0.09)
        XCTAssertLessThan(max(darkRed, darkGreen, darkBlue), 0.16)
        XCTAssertLessThan(max(lightRed, lightGreen, lightBlue), 0.25)
        XCTAssertLessThan(max(fill.redComponent, fill.greenComponent, fill.blueComponent) - min(fill.redComponent, fill.greenComponent, fill.blueComponent), 0.01)
    }

    func testWindowIntentPreviewAccentMatchesMatteFill() {
        let accent = NSColor(cgColor: WindowIntentPreviewPalette.accent(alpha: 0.42))
            .orDie()
            .usingColorSpace(.deviceRGB)
            .orDie()
        let matte = mattePanelNSColor
            .usingColorSpace(.deviceRGB)
            .orDie()

        XCTAssertEqual(accent.redComponent, matte.redComponent, accuracy: 0.001)
        XCTAssertEqual(accent.greenComponent, matte.greenComponent, accuracy: 0.001)
        XCTAssertEqual(accent.blueComponent, matte.blueComponent, accuracy: 0.001)
        XCTAssertEqual(accent.alphaComponent, matte.alphaComponent, accuracy: 0.001)
    }

    @MainActor
    func testHudPanelBaseDoesNotPaintSystemHudBackdrop() {
        let panel = NSPanelHud()

        XCTAssertFalse(panel.styleMask.contains(.hudWindow))
        XCTAssertFalse(panel.isOpaque)
    }

    @MainActor
    func testWindowIntentPreviewPanelRendersGrayTranslucentSurface() throws {
        let frame = CGRect(x: 120, y: 120, width: 240, height: 160)
        let background = NSWindow(
            contentRect: frame.insetBy(dx: -12, dy: -12),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        background.isOpaque = true
        background.backgroundColor = .white
        background.level = NSWindow.Level(rawValue: WinMuxPanelLayer.windowIntentPreview.level.rawValue - 1)
        background.orderFrontRegardless()
        defer { background.orderOut(nil) }

        let panel = WindowTabDropPreviewPanel.shared
        panel.show(WindowTabDropPreviewViewModel(
            containerFrame: frame,
            frame: frame,
            title: "Preview",
            subtitle: "Preview",
            style: .stackSplit,
            geometry: .rounded,
            isGroup: false,
            referenceWindowId: nil,
            isPointerSettled: true,
            zones: [],
        ))
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        defer { panel.hide() }
        guard let panelBounds = cgWindowBounds(windowNumber: panel.windowNumber),
              let cgImage = CGWindowListCreateImage(
                  panelBounds,
                  .optionIncludingWindow,
                  CGWindowID(panel.windowNumber),
                  [.nominalResolution],
              )
        else {
            throw XCTSkip("Could not capture intent preview panel window")
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let sample = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2).orDie()
            .usingColorSpace(.deviceRGB).orDie()
        XCTAssertGreaterThan(min(sample.redComponent, sample.greenComponent, sample.blueComponent), 0.12)
        XCTAssertLessThan(max(sample.redComponent, sample.greenComponent, sample.blueComponent), 0.28)
    }

    @MainActor
    func testResizePreviewWeightMapDoesNotMutateWeightsUntilCommit() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.changeOrientation(.h)
        root.layout = .tiles

        let left = TestWindow.new(id: 1, parent: root, adaptiveWeight: 500)
        let right = TestWindow.new(id: 2, parent: root, adaptiveWeight: 500)
        left.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 500, height: 400)
        left.lastAppliedLayoutVirtualRect = left.lastAppliedLayoutPhysicalRect
        right.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 500, topLeftY: 0, width: 500, height: 400)
        right.lastAppliedLayoutVirtualRect = right.lastAppliedLayoutPhysicalRect

        let proposedRect = Rect(topLeftX: 0, topLeftY: 0, width: 620, height: 400)
        let weightMap = proposedResizeWeightMap(left, rect: proposedRect).orDie()

        XCTAssertEqual(left.hWeight, 500)
        XCTAssertEqual(right.hWeight, 500)
        XCTAssertEqual(weightMap.weight(for: left, orientation: .h), 620)
        XCTAssertEqual(weightMap.weight(for: right, orientation: .h), 380)

        applyResizeWithMouse(left, rect: proposedRect)

        XCTAssertEqual(left.hWeight, 620)
        XCTAssertEqual(right.hWeight, 380)
        cancelManipulatedWithMouseState()
    }

    func testWindowTabStripDragInProgressIgnoresRegularWindowMove() {
        XCTAssertFalse(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
        ))
        XCTAssertFalse(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: true,
        ))
    }

}
