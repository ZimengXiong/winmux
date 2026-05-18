import AppKit

@MainActor
func windowTabOccludingFloatingWindowFrames(in workspace: Workspace) async -> [CGRect] {
    var frames: [CGRect] = []
    for window in workspace.floatingWindows where window.isBound {
        let rect: Rect?
        if let cachedRect = window.lastKnownActualRect {
            rect = cachedRect
        } else {
            rect = try? await window.getAxRect()
        }
        guard let rect, rect.width > 0, rect.height > 0 else { continue }
        frames.append(rect.toAppKitScreenRect.alignedToBackingPixels())
    }
    return frames
}

func windowTabLocalOcclusionRects(panelFrame: CGRect, occludingScreenFrames: [CGRect]) -> [CGRect] {
    occludingScreenFrames.compactMap { screenFrame in
        guard screenFrame.intersects(panelFrame) else { return nil }
        let local = CGRect(
            x: screenFrame.minX - panelFrame.minX,
            y: panelFrame.maxY - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height,
        )
        let clipped = local.intersection(CGRect(origin: .zero, size: panelFrame.size))
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }
}

func windowTabLocalFrame(panelFrame: CGRect, childFrame: CGRect) -> CGRect {
    CGRect(
        x: childFrame.minX - panelFrame.minX,
        y: panelFrame.maxY - childFrame.maxY,
        width: childFrame.width,
        height: childFrame.height,
    )
}
