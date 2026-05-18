import AppKit

func debugDescribe(_ rect: Rect?) -> String {
    guard let rect else { return "nil" }
    return "(\(rect.topLeftX), \(rect.topLeftY), \(rect.width), \(rect.height))"
}

func debugDescribe(_ point: CGPoint) -> String {
    "(\(point.x), \(point.y))"
}

func debugDescribe(_ subject: WindowDragSubject) -> String {
    switch subject {
        case .window: "window"
        case .group: "group"
    }
}

func debugDescribe(_ kind: WindowDragIntentKind) -> String {
    switch kind {
        case .tabStack(let targetWindowId):
            "tabStack(target:\(targetWindowId))"
        case .detachTab(let windowId):
            "detachTab(window:\(windowId))"
        case .stackSplit(let targetWindowId, let position):
            "stackSplit(target:\(targetWindowId), position:\(position))"
        case .swap(let targetWindowId):
            "swap(target:\(targetWindowId))"
        case .moveToWorkspace(let workspaceName):
            "moveToWorkspace(\(workspaceName))"
        case .createWorkspace:
            "createWorkspace"
        case .sidebarHover:
            "sidebarHover"
    }
}
