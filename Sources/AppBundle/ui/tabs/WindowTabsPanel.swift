import AppKit
import SwiftUI

let windowTabVisualPanelPrefix = "WinMux.windowTabs.visual."
let windowTabStripPanelPrefix = "WinMux.windowTabs.strip."
let windowTabDropPreviewPanelId = "WinMux.windowTabs.dropPreview"
let windowDragCursorProxyPanelId = "WinMux.windowTabs.cursorProxy"
let windowPreviewCornerAlphaThreshold: CGFloat = 0.3
let windowPreviewCornerScanLimit = 48
let windowTabReorderDropClearDelay: TimeInterval = 0.24

@MainActor
var windowPreviewCornerRadiusCache: [UInt32: CGFloat] = [:]

// macOS 27 unified the window corner radius across the system, so a radius measured from any
// window is a better fallback for unmeasurable windows than a hardcoded constant.
@MainActor
private var lastMeasuredWindowCornerRadius: CGFloat? = nil

@MainActor
func estimatedWindowPreviewCornerRadius(for windowId: UInt32) -> CGFloat {
    if let cached = windowPreviewCornerRadiusCache[windowId] {
        return cached
    }
    guard CGPreflightScreenCaptureAccess(),
          let resolvedRadius = estimateWindowPreviewCornerRadiusFromImage(windowId: windowId)
    else {
        return lastMeasuredWindowCornerRadius ?? windowTabPreviewCornerRadius
    }
    windowPreviewCornerRadiusCache[windowId] = resolvedRadius
    lastMeasuredWindowCornerRadius = resolvedRadius
    return resolvedRadius
}

func estimateWindowPreviewCornerRadiusFromImage(windowId: UInt32) -> CGFloat? {
    guard let cgImage = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(windowId),
        [.boundsIgnoreFraming, .nominalResolution],
    ) else {
        return nil
    }
    return estimateTopCornerRadius(in: cgImage)
}

func estimateTopCornerRadius(in image: CGImage) -> CGFloat? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    let maxScan = min(windowPreviewCornerScanLimit, width / 2, height / 2)
    guard maxScan > 0 else { return nil }

    func alphaAt(x: Int, yFromTop: Int) -> CGFloat {
        let bitmapY = height - 1 - yFromTop
        guard bitmapY >= 0,
              bitmapY < height,
              x >= 0,
              x < width
        else {
            return 0
        }
        return bitmap.colorAt(x: x, y: bitmapY)?.alphaComponent ?? 0
    }

    // For a corner of radius r, the first opaque pixel at scan depth y sits at inset
    // i = r - sqrt(r^2 - (r-y)^2). Solving for r: r = (i + y) + sqrt(2*i*y). Each (inset, row)
    // sample therefore yields a direct radius estimate. (The previous implementation compared
    // raw insets across rows, which only equal the radius at row 0 — the samples disagreed by
    // design, the consistency check failed, and detection almost always fell back to the
    // hardcoded default.)
    func radiusEstimate(inset: Int, depth: Int) -> Double {
        Double(inset + depth) + (2.0 * Double(inset) * Double(depth)).squareRoot()
    }

    var estimates: [Double] = []

    // Scan horizontal insets at multiple rows from top (both edges)
    for row in 0 ..< min(4, maxScan) {
        for step in 0 ..< maxScan {
            if alphaAt(x: step, yFromTop: row) > windowPreviewCornerAlphaThreshold {
                estimates.append(radiusEstimate(inset: step, depth: row))
                break
            }
        }
        for step in 0 ..< maxScan {
            if alphaAt(x: width - 1 - step, yFromTop: row) > windowPreviewCornerAlphaThreshold {
                estimates.append(radiusEstimate(inset: step, depth: row))
                break
            }
        }
    }

    // Scan vertical insets at leftmost and rightmost columns from top (depth 0 along x)
    for x in [0, width - 1] {
        for step in 0 ..< maxScan {
            if alphaAt(x: x, yFromTop: step) > windowPreviewCornerAlphaThreshold {
                estimates.append(Double(step))
                break
            }
        }
    }

    guard estimates.count >= 6 else { return nil }

    let sorted = estimates.sorted()
    let median = sorted[sorted.count / 2]

    let consistent = estimates.filter { abs($0 - median) <= 3 }
    guard Double(consistent.count) >= Double(estimates.count) * 0.6 else {
        return nil
    }

    guard median >= 4 else { return nil }
    return CGFloat((median * 2).rounded() / 2)
}
