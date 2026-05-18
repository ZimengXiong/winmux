struct WindowTabPendingReorderDrop: Equatable {
    let windowId: UInt32
    let sourceIndex: Int
    let targetIndex: Int
    let orderBeforeDrop: [UInt32]
}
