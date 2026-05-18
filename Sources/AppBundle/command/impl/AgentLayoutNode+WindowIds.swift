extension AgentLayoutNode {
    func collectWindowIds(result: inout Set<UInt32>) {
        switch self {
            case .split(_, let children, _):
                for child in children { child.collectWindowIds(result: &result) }
            case .window(let windowId, _):
                result.insert(windowId)
            case .tabGroup(_, let tabs, _, _):
                for tab in tabs { result.insert(tab) }
        }
    }

    func collectWindowIds(result: inout [UInt32]) {
        switch self {
            case .split(_, let children, _):
                for child in children { child.collectWindowIds(result: &result) }
            case .window(let windowId, _):
                result.append(windowId)
            case .tabGroup(_, let tabs, _, _):
                result.append(contentsOf: tabs)
        }
    }
}
