import AppKit

final class WindowShakeTilingPlacement {
    weak var parent: TilingContainer?
    let adaptiveWeight: CGFloat
    let index: Int

    init?(_ binding: BindingData) {
        guard let parent = binding.parent as? TilingContainer else { return nil }
        self.parent = parent
        adaptiveWeight = binding.adaptiveWeight
        index = binding.index
    }
}

struct WindowShakeGestureConfiguration: Equatable {
    var minimumStrokeDistance = CGFloat(55)
    var minimumTotalDistance = CGFloat(240)
    var requiredReversals = 3
    var maximumDuration: TimeInterval = 0.9
    var maximumSampleGap: TimeInterval = 0.25
    var horizontalDominanceRatio = CGFloat(1.25)
    var minimumSampleDistance = CGFloat(2)
}

struct WindowShakeGestureRecognizer {
    let configuration: WindowShakeGestureConfiguration

    private(set) var didRecognize = false
    private var firstTimestamp: TimeInterval?
    private var previousSample: MousePointerSample?
    private var direction = 0
    private var strokeDistance = CGFloat.zero
    private var totalDistance = CGFloat.zero
    private var reversalCount = 0

    init(configuration: WindowShakeGestureConfiguration = WindowShakeGestureConfiguration()) {
        self.configuration = configuration
    }

    mutating func observe(_ sample: MousePointerSample) -> Bool {
        guard !didRecognize else { return false }
        guard let previousSample, let firstTimestamp else {
            begin(with: sample)
            return false
        }
        if sample.timestamp - previousSample.timestamp > configuration.maximumSampleGap ||
            sample.timestamp - firstTimestamp > configuration.maximumDuration
        {
            begin(with: sample)
            return false
        }

        self.previousSample = sample
        let dx = sample.point.x - previousSample.point.x
        let dy = sample.point.y - previousSample.point.y
        let horizontalDistance = abs(dx)
        guard horizontalDistance >= configuration.minimumSampleDistance else { return false }
        guard horizontalDistance >= abs(dy) * configuration.horizontalDominanceRatio else {
            resetStroke()
            return false
        }

        let newDirection = dx < 0 ? -1 : 1
        totalDistance += horizontalDistance
        if direction == 0 {
            direction = newDirection
            strokeDistance = horizontalDistance
        } else if newDirection == direction {
            strokeDistance += horizontalDistance
        } else if strokeDistance >= configuration.minimumStrokeDistance {
            reversalCount += 1
            direction = newDirection
            strokeDistance = horizontalDistance
        } else {
            // Treat a short reversal as hand jitter. Only change direction if it fully
            // cancels the current partial stroke.
            strokeDistance -= horizontalDistance
            if strokeDistance < 0 {
                direction = newDirection
                strokeDistance = -strokeDistance
            }
        }

        didRecognize = reversalCount >= configuration.requiredReversals &&
            totalDistance >= configuration.minimumTotalDistance
        return didRecognize
    }

    private mutating func begin(with sample: MousePointerSample) {
        firstTimestamp = sample.timestamp
        previousSample = sample
        resetStroke()
        totalDistance = 0
        reversalCount = 0
    }

    private mutating func resetStroke() {
        direction = 0
        strokeDistance = 0
    }
}

func shouldRecognizeWindowShake(
    kind: MouseManipulationKind,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
    isPointerInsideSidebar: Bool,
) -> Bool {
    kind == .move &&
        subject == .window &&
        detachOrigin == .window &&
        !startedInSidebar &&
        !isPointerInsideSidebar
}
