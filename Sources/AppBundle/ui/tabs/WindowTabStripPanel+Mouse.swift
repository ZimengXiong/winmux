import AppKit
import SwiftUI

extension WindowTabStripPanel {
    func shouldUpdate(content: WindowTabGroupChromeContent, strip: WindowTabStripViewModel) -> Bool {
        let frameChanged = currentPanelFrame != strip.frame
        let occlusionChanged = tabStripIsOccludedByFloatingWindow != strip.tabStripIsOccludedByFloatingWindow
        if currentContent == content, !frameChanged, !occlusionChanged, isVisible {
            updateMousePolicy()
            return false
        }
        return true
    }

    func updateMousePolicy() {
        let ignoresForMouseManipulation = currentlyManipulatedWithMouseWindowId != nil &&
            shouldIgnoreWindowTabStripMouseEventsDuringDrag(detachOrigin: getCurrentMouseTabDetachOrigin())
        ignoresMouseEvents = externallyIgnoresMouseEvents ||
            ignoresForMouseManipulation ||
            tabStripIsOccludedByFloatingWindow
    }
}

final class WindowTabStripHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
