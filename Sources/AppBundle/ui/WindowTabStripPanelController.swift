@MainActor
final class WindowTabStripPanelController {
    static let shared = WindowTabStripPanelController()

    enum MouseInteractionChromeMode: Equatable {
        case frameOnly
        case hidden
    }

    var visualPanels: [ObjectIdentifier: WindowTabGroupVisualPanel] = [:]
    var stripPanels: [ObjectIdentifier: WindowTabStripPanel] = [:]
    var transientResizeTabGroupId: ObjectIdentifier? = nil
    var mouseInteractionChromeMode: MouseInteractionChromeMode? = nil
    var hiddenPassiveTabGroupChromeIds: Set<ObjectIdentifier> = []

    private init() {}
}
