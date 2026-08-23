import AppKit

/// Keep a resized tile large enough to remain a usable, non-overlapping participant in its
/// split. This matches the minimum size used by the mouse resize gesture itself.
let minimumTiledResizeWeight = CGFloat(80)

struct TiledResizeAdjustment {
    let weight: CGFloat
    let multiplier: CGFloat
}

/// Clamps a shared resize delta so none of its affected tiled nodes is made smaller than the
/// resize floor. Nodes which are already below the floor are allowed to stay at their current
/// size, but cannot be made smaller; this keeps dense pre-existing layouts operable.
func constrainedTiledResizeDiff(
    _ requestedDiff: CGFloat,
    adjustments: [TiledResizeAdjustment]
) -> CGFloat {
    var lowerBound = -CGFloat.infinity
    var upperBound = CGFloat.infinity

    for adjustment in adjustments where adjustment.multiplier != 0 {
        let floor = min(adjustment.weight, minimumTiledResizeWeight)
        let boundary = (floor - adjustment.weight) / adjustment.multiplier
        if adjustment.multiplier > 0 {
            lowerBound = max(lowerBound, boundary)
        } else {
            upperBound = min(upperBound, boundary)
        }
    }

    return min(max(requestedDiff, lowerBound), upperBound)
}
