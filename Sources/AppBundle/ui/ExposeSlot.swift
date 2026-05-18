enum ExposeSlot: Identifiable {
    case single(ExposeWindowItem, expandedGroupId: String?, groupBadgeLabel: String?)
    case stack(ExposeTabGroup)

    var id: String {
        switch self {
            case .single(let window, let expandedGroupId, _):
                if let expandedGroupId { return "eg-\(expandedGroupId)-\(window.id)" }
                return "w-\(window.id)"
            case .stack(let group):
                return "g-\(group.id)"
        }
    }

    var span: Int {
        1
    }
}
