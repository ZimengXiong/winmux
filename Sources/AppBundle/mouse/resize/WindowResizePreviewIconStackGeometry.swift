import AppKit

func windowResizePreviewStackOffset(_ index: Int, iconCount: Int, size: CGFloat) -> CGSize {
    let offsets = [
        CGSize(width: 0, height: -size * 0.08),
        CGSize(width: -size * 0.24, height: size * 0.16),
        CGSize(width: size * 0.24, height: size * 0.18),
        CGSize(width: -size * 0.02, height: size * 0.32),
    ]
    let offset = offsets[min(index, offsets.count - 1)]
    return iconCount == 2 && index == 1 ? CGSize(width: -size * 0.18, height: size * 0.16) : offset
}

func windowResizePreviewStackRotation(_ index: Int) -> Double {
    let rotations = [-4.0, 7.0, -8.0, 3.0]
    return rotations[min(index, rotations.count - 1)]
}
