import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore

@MainActor
final class DisplayRefreshDriver: @unchecked Sendable {
    static let shared = DisplayRefreshDriver()

    private struct Subscription {
        weak var owner: AnyObject?
        let callback: (CFTimeInterval) -> Void
    }

    private var subscriptions: [ObjectIdentifier: Subscription] = [:]
    private var displayLink: CVDisplayLink?
    private var fallbackTimer: Timer?

    private init() {}

    func add(owner: AnyObject, callback: @escaping (CFTimeInterval) -> Void) {
        subscriptions[ObjectIdentifier(owner)] = Subscription(owner: owner, callback: callback)
        startIfNeeded()
    }

    func remove(owner: AnyObject) {
        subscriptions.removeValue(forKey: ObjectIdentifier(owner))
        stopIfIdle()
    }

    private func startIfNeeded() {
        guard !subscriptions.isEmpty, displayLink == nil, fallbackTimer == nil else { return }
        if startDisplayLink() {
            return
        }
        startFallbackTimer()
    }

    private func startDisplayLink() -> Bool {
        var rawLink: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&rawLink) == kCVReturnSuccess,
              let rawLink
        else {
            return false
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard CVDisplayLinkSetOutputCallback(rawLink, Self.displayLinkCallback, userInfo) == kCVReturnSuccess,
              CVDisplayLinkStart(rawLink) == kCVReturnSuccess
        else {
            return false
        }
        displayLink = rawLink
        return true
    }

    private func startFallbackTimer() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                DisplayRefreshDriver.shared.fire(timestamp: CACurrentMediaTime())
            }
        }
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopIfIdle() {
        pruneReleasedOwners()
        guard subscriptions.isEmpty else { return }
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func pruneReleasedOwners() {
        subscriptions = subscriptions.filter { $0.value.owner != nil }
    }

    private func fire(timestamp: CFTimeInterval) {
        pruneReleasedOwners()
        guard !subscriptions.isEmpty else {
            stopIfIdle()
            return
        }
        for subscription in subscriptions.values {
            subscription.callback(timestamp)
        }
    }

    private nonisolated static let displayLinkCallback: CVDisplayLinkOutputCallback = { _, now, _, _, _, userInfo in
        guard let userInfo else { return kCVReturnSuccess }
        let driver = Unmanaged<DisplayRefreshDriver>.fromOpaque(userInfo).takeUnretainedValue()
        let hostFrequency = CVGetHostClockFrequency()
        let timestamp = hostFrequency > 0 ? Double(now.pointee.hostTime) / hostFrequency : CACurrentMediaTime()
        DispatchQueue.main.async {
            Task { @MainActor in
                driver.fire(timestamp: timestamp)
            }
        }
        return kCVReturnSuccess
    }
}

func displayRefreshEaseInOut(_ progress: CGFloat) -> CGFloat {
    let clamped = min(max(progress, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
}

func displayRefreshInterpolate(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
    start + (end - start) * progress
}

func displayRefreshInterpolate(_ start: CGRect, _ end: CGRect, progress: CGFloat) -> CGRect {
    CGRect(
        x: displayRefreshInterpolate(start.minX, end.minX, progress: progress),
        y: displayRefreshInterpolate(start.minY, end.minY, progress: progress),
        width: displayRefreshInterpolate(start.width, end.width, progress: progress),
        height: displayRefreshInterpolate(start.height, end.height, progress: progress),
    )
}
