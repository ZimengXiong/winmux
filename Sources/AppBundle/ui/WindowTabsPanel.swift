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

@MainActor
func estimatedWindowPreviewCornerRadius(for windowId: UInt32) -> CGFloat {
    if let cached = windowPreviewCornerRadiusCache[windowId] {
        return cached
    }
    guard CGPreflightScreenCaptureAccess(),
          let resolvedRadius = estimateWindowPreviewCornerRadiusFromImage(windowId: windowId)
    else {
        return windowTabPreviewCornerRadius
    }
    windowPreviewCornerRadiusCache[windowId] = resolvedRadius
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

    var samples: [Int] = []

    // Scan horizontal insets at multiple rows from top (both edges)
    for row in 0 ..< min(4, maxScan) {
        for step in 0 ..< maxScan {
            if alphaAt(x: step, yFromTop: row) > windowPreviewCornerAlphaThreshold {
                samples.append(step)
                break
            }
        }
        for step in 0 ..< maxScan {
            if alphaAt(x: width - 1 - step, yFromTop: row) > windowPreviewCornerAlphaThreshold {
                samples.append(step)
                break
            }
        }
    }

    // Scan vertical insets at leftmost and rightmost columns from top
    for x in [0, width - 1] {
        for step in 0 ..< maxScan {
            if alphaAt(x: x, yFromTop: step) > windowPreviewCornerAlphaThreshold {
                samples.append(step)
                break
            }
        }
    }

    guard samples.count >= 6 else { return nil }

    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]

    let consistent = samples.filter { abs($0 - median) <= 2 }
    guard Double(consistent.count) >= Double(samples.count) * 0.6 else {
        return nil
    }

    guard median >= 4 else { return nil }
    return CGFloat(median)
}
