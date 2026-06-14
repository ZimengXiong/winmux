enum TrayItemType: String, Hashable {
    case mode
    case workspace
}

private let validLetters = "A" ... "Z"

struct TrayItem: Hashable, Identifiable {
    let type: TrayItemType
    let name: String
    let displayName: String
    let isActive: Bool
    let hasFullscreenWindows: Bool

    init(type: TrayItemType, name: String, displayName: String? = nil, isActive: Bool, hasFullscreenWindows: Bool) {
        self.type = type
        self.name = name
        self.displayName = displayName ?? name
        self.isActive = isActive
        self.hasFullscreenWindows = hasFullscreenWindows
    }

    var id: String {
        type.rawValue + name
    }

    var systemImageName: String? {
        guard displayName == name else { return nil }
        guard isValidSystemImageName else { return nil }
        let lowercasedName = name.lowercased()
        return type == .mode
            ? "\(lowercasedName).circle"
            : "\(lowercasedName).square\(isActive ? ".fill" : "")"
    }

    private var isValidSystemImageName: Bool {
        if let number = Int(name) {
            return (0 ... 50).contains(number)
        }
        return name.count == 1 && validLetters.contains(name)
    }
}
