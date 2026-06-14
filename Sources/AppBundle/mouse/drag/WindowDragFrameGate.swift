import CoreGraphics
import QuartzCore

struct WindowDragFrameGateState: Equatable {
    let point: CGPoint
    let timestamp: CFTimeInterval
    let velocity: CGFloat
    let isSettled: Bool
}

struct WindowDragFrameGateCore {
    var minimumInterval: CFTimeInterval = 1.0 / 120.0
    var settledVelocityThreshold: CGFloat = 72

    private var lastSample: WindowDragFrameGateState?
    private(set) var state: WindowDragFrameGateState?

    init(
        minimumInterval: CFTimeInterval = 1.0 / 120.0,
        settledVelocityThreshold: CGFloat = 72,
    ) {
        self.minimumInterval = minimumInterval
        self.settledVelocityThreshold = settledVelocityThreshold
    }

    mutating func shouldProcess(
        point: CGPoint,
        timestamp: CFTimeInterval,
        force: Bool = false,
    ) -> Bool {
        guard let lastSample else {
            record(point: point, timestamp: timestamp, velocity: 0)
            return true
        }

        let elapsed = timestamp - lastSample.timestamp
        guard force || elapsed >= minimumInterval else {
            return false
        }

        let distance = hypot(point.x - lastSample.point.x, point.y - lastSample.point.y)
        let velocity = elapsed > 0 ? distance / CGFloat(elapsed) : 0
        record(point: point, timestamp: timestamp, velocity: velocity)
        return true
    }

    mutating func reset() {
        lastSample = nil
        state = nil
    }

    private mutating func record(point: CGPoint, timestamp: CFTimeInterval, velocity: CGFloat) {
        let nextState = WindowDragFrameGateState(
            point: point,
            timestamp: timestamp,
            velocity: velocity,
            isSettled: velocity <= settledVelocityThreshold,
        )
        lastSample = nextState
        state = nextState
    }
}

@MainActor
final class WindowDragFrameGate {
    static let shared = WindowDragFrameGate()

    private var gatesByWindowId: [UInt32: WindowDragFrameGateCore] = [:]

    private init() {}

    func shouldProcess(windowId: UInt32, point: CGPoint, force: Bool = false) -> Bool {
        var gate = gatesByWindowId[windowId] ?? WindowDragFrameGateCore()
        let shouldProcess = gate.shouldProcess(point: point, timestamp: CACurrentMediaTime(), force: force)
        gatesByWindowId[windowId] = gate
        return shouldProcess
    }

    func state(for windowId: UInt32) -> WindowDragFrameGateState? {
        gatesByWindowId[windowId]?.state
    }

    func reset(windowId: UInt32) {
        gatesByWindowId.removeValue(forKey: windowId)
    }

    func resetAll() {
        gatesByWindowId.removeAll()
    }
}
