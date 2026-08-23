import Combine
import CoreGraphics

struct WindowTabPendingReorderDrop: Equatable {
    let stripId: ObjectIdentifier?
    let windowId: UInt32
    let sourceIndex: Int
    let targetIndex: Int
    let orderBeforeDrop: [UInt32]
    let sourceVisualOffset: CGFloat?
}

/// Narrow observable for the drag-reorder preview so tab strip views don't have to observe the
/// whole TrayMenuModel (which republishes on every refresh session) just for this one value.
/// Writes happen on every drag tick, so the setter is equality-guarded.
@MainActor
final class WindowTabReentryPreviewModel: ObservableObject {
    static let shared = WindowTabReentryPreviewModel()

    @Published private(set) var value: WindowTabPendingReorderDrop? = nil

    func set(_ newValue: WindowTabPendingReorderDrop?) {
        if value != newValue {
            value = newValue
        }
    }
}
