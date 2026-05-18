import Foundation

enum WindowDropZone: String, CaseIterable, Equatable {
    case tab
    case left
    case right
    case top
    case bottom
    case middle

    var stackSplitPosition: WindowStackSplitPosition? {
        switch self {
            case .left: .left
            case .right: .right
            case .top: .above
            case .bottom: .below
            case .tab, .middle: nil
        }
    }
}

struct WindowDropIntent: Equatable {
    let sourceWindowId: UInt32
    let targetWindowId: UInt32
    let zone: WindowDropZone
}
