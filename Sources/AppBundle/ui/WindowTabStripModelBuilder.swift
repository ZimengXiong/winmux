import AppKit

@MainActor
func buildWindowTabStripViewModelsFromChromeItems() async -> [WindowTabStripViewModel] {
    var occlusionsByWorkspace: [String: [CGRect]] = [:]
    var strips: [WindowTabStripViewModel] = []
    for item in await buildWindowTabChromeItemsFromSource10Tree() {
        guard let groupFrame = item.visibleFrame else { continue }
        let occlusions = await cachedWindowTabOcclusions(
            workspaceName: item.workspaceName,
            cache: &occlusionsByWorkspace,
        )
        strips.append(WindowTabStripViewModel(
            id: item.id,
            workspaceName: item.workspaceName,
            frame: windowTabBarFrame(fromGroupFrame: groupFrame),
            groupFrame: groupFrame,
            activeWindowId: item.activeWindowId,
            activeWindowCornerRadius: windowTabGroupAppCornerRadius(activeWindowId: item.activeWindowId),
            tabs: item.tabs.map { $0.legacyTabItem(workspaceName: item.workspaceName) },
            occludingFloatingWindowFrames: occlusions,
        ))
    }
    return strips
}
