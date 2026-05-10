import CoreGraphics
import Foundation

private let resizeGestureMinimumWidth = CGFloat(80)
private let resizeGestureMinimumHeight = CGFloat(80)
private let resizeGestureChangedEdgeThreshold = CGFloat(2)
private let resizeGestureCandidateEdgeThreshold = CGFloat(32)

struct ResizeGestureEdges: Equatable {
    let left: Bool
    let right: Bool
    let up: Bool
    let down: Bool

    var hasAny: Bool { left || right || up || down }
}

struct ResizeGestureMouseOffset: Equatable {
    var left: CGFloat
    var right: CGFloat
    var up: CGFloat
    var down: CGFloat
}

struct ResizeGestureSessionState {
    let windowId: UInt32
    let baseRect: Rect
    var edges: ResizeGestureEdges
    var mouseOffset: ResizeGestureMouseOffset
    var latestRect: Rect
    var lastCalibrationTimestamp: TimeInterval

    func predictedRect(mouse: CGPoint) -> Rect {
        var minX = baseRect.minX
        var maxX = baseRect.maxX
        var minY = baseRect.minY
        var maxY = baseRect.maxY

        if edges.left {
            minX = min(mouse.x - mouseOffset.left, maxX - resizeGestureMinimumWidth)
        }
        if edges.right {
            maxX = max(mouse.x - mouseOffset.right, minX + resizeGestureMinimumWidth)
        }
        if edges.up {
            minY = min(mouse.y - mouseOffset.up, maxY - resizeGestureMinimumHeight)
        }
        if edges.down {
            maxY = max(mouse.y - mouseOffset.down, minY + resizeGestureMinimumHeight)
        }

        return Rect(topLeftX: minX, topLeftY: minY, width: maxX - minX, height: maxY - minY)
    }

    mutating func calibrate(observedRect: Rect, mouse: CGPoint, timestamp: TimeInterval) {
        let observedEdges = resizeGestureEdgesFromDelta(baseRect: baseRect, observedRect: observedRect)
        if observedEdges.hasAny {
            edges = observedEdges
        }
        if edges.left {
            mouseOffset.left = mouse.x - observedRect.minX
        }
        if edges.right {
            mouseOffset.right = mouse.x - observedRect.maxX
        }
        if edges.up {
            mouseOffset.up = mouse.y - observedRect.minY
        }
        if edges.down {
            mouseOffset.down = mouse.y - observedRect.maxY
        }
        latestRect = observedRect
        lastCalibrationTimestamp = timestamp
    }
}

func makeResizeGestureSession(
    windowId: UInt32,
    baseRect: Rect,
    observedRect: Rect,
    mouse: CGPoint,
    edges: ResizeGestureEdges,
    timestamp: TimeInterval,
) -> ResizeGestureSessionState? {
    guard edges.hasAny else { return nil }
    return ResizeGestureSessionState(
        windowId: windowId,
        baseRect: baseRect,
        edges: edges,
        mouseOffset: ResizeGestureMouseOffset(
            left: mouse.x - observedRect.minX,
            right: mouse.x - observedRect.maxX,
            up: mouse.y - observedRect.minY,
            down: mouse.y - observedRect.maxY,
        ),
        latestRect: observedRect,
        lastCalibrationTimestamp: timestamp,
    )
}

func resizeGestureEdges(baseRect: Rect, observedRect: Rect, mouse: CGPoint) -> ResizeGestureEdges {
    let edges = resizeGestureEdgesFromDelta(baseRect: baseRect, observedRect: observedRect)
    let fallback = resizeGestureCandidateEdges(mouse: mouse, rect: observedRect)
    var left = edges.left
    var right = edges.right
    var up = edges.up
    var down = edges.down
    if !left, !right {
        left = fallback.left
        right = fallback.right
    }
    if !up, !down {
        up = fallback.up
        down = fallback.down
    }

    return ResizeGestureEdges(left: left, right: right, up: up, down: down)
}

func resizeGestureCandidateEdges(mouse: CGPoint, rect: Rect) -> ResizeGestureEdges {
    resizeGestureEdgesNear(mouse: mouse, rect: rect, threshold: resizeGestureCandidateEdgeThreshold)
}

func resizeGestureEdgesFromDelta(baseRect: Rect, observedRect: Rect) -> ResizeGestureEdges {
    let leftDiff = abs(baseRect.minX - observedRect.minX)
    let rightDiff = abs(baseRect.maxX - observedRect.maxX)
    let upDiff = abs(baseRect.minY - observedRect.minY)
    let downDiff = abs(baseRect.maxY - observedRect.maxY)

    var left = leftDiff > resizeGestureChangedEdgeThreshold
    var right = rightDiff > resizeGestureChangedEdgeThreshold
    var up = upDiff > resizeGestureChangedEdgeThreshold
    var down = downDiff > resizeGestureChangedEdgeThreshold

    if left, right {
        left = leftDiff >= rightDiff
        right = !left
    }
    if up, down {
        up = upDiff >= downDiff
        down = !up
    }

    return ResizeGestureEdges(left: left, right: right, up: up, down: down)
}

func resizeGestureEdgesNear(mouse: CGPoint, rect: Rect, threshold: CGFloat) -> ResizeGestureEdges {
    let leftDistance = abs(mouse.x - rect.minX)
    let rightDistance = abs(mouse.x - rect.maxX)
    let upDistance = abs(mouse.y - rect.minY)
    let downDistance = abs(mouse.y - rect.maxY)

    let left: Bool
    let right: Bool
    if min(leftDistance, rightDistance) <= threshold {
        left = leftDistance <= rightDistance
        right = !left
    } else {
        left = false
        right = false
    }

    let up: Bool
    let down: Bool
    if min(upDistance, downDistance) <= threshold {
        up = upDistance <= downDistance
        down = !up
    } else {
        up = false
        down = false
    }

    return ResizeGestureEdges(left: left, right: right, up: up, down: down)
}
