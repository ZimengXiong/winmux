import CoreGraphics
import Foundation

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
    let edges: ResizeGestureEdges
    var mouseOffset: ResizeGestureMouseOffset
    var latestRect: Rect
    var lastCalibrationTimestamp: TimeInterval

    func predictedRect(mouse: CGPoint) -> Rect {
        let minimumWidth = CGFloat(80)
        let minimumHeight = CGFloat(80)
        var minX = baseRect.minX
        var maxX = baseRect.maxX
        var minY = baseRect.minY
        var maxY = baseRect.maxY

        if edges.left {
            minX = min(mouse.x - mouseOffset.left, maxX - minimumWidth)
        }
        if edges.right {
            maxX = max(mouse.x - mouseOffset.right, minX + minimumWidth)
        }
        if edges.up {
            minY = min(mouse.y - mouseOffset.up, maxY - minimumHeight)
        }
        if edges.down {
            maxY = max(mouse.y - mouseOffset.down, minY + minimumHeight)
        }

        return Rect(topLeftX: minX, topLeftY: minY, width: maxX - minX, height: maxY - minY)
    }

    mutating func calibrate(observedRect: Rect, mouse: CGPoint, timestamp: TimeInterval) {
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
    let threshold = CGFloat(2)
    let leftDiff = abs(baseRect.minX - observedRect.minX)
    let rightDiff = abs(baseRect.maxX - observedRect.maxX)
    let upDiff = abs(baseRect.minY - observedRect.minY)
    let downDiff = abs(baseRect.maxY - observedRect.maxY)

    var left = leftDiff > threshold
    var right = rightDiff > threshold
    var up = upDiff > threshold
    var down = downDiff > threshold

    if left, right {
        left = leftDiff >= rightDiff
        right = !left
    }
    if up, down {
        up = upDiff >= downDiff
        down = !up
    }

    let fallback = resizeGestureEdgesNear(mouse: mouse, rect: observedRect, threshold: 96)
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
