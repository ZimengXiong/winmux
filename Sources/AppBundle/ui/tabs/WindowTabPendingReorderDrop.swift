import CoreGraphics

struct WindowTabPendingReorderDrop: Equatable {
    let stripId: ObjectIdentifier?
    let windowId: UInt32
    let sourceIndex: Int
    let targetIndex: Int
    let orderBeforeDrop: [UInt32]
    let sourceVisualOffset: CGFloat?
}
