import AppKit

extension WorkspaceSidebarProjectMenuCoordinator {
    func colorMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addAutomaticColorItem(to: menu)
        menu.addItem(.separator())
        for preset in workspaceSidebarProjectColorPresets {
            let item = NSMenuItem(title: preset.name, action: #selector(setColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.hex
            item.state = selectedProjectColorHex == preset.hex ? .on : .off
            item.image = workspaceSidebarProjectColorSwatchImage(hex: preset.hex, isSelected: selectedProjectColorHex == preset.hex)
            menu.addItem(item)
        }
        return menu
    }

    private func addAutomaticColorItem(to menu: NSMenu) {
        let automaticItem = NSMenuItem(title: "Auto", action: #selector(setColor(_:)), keyEquivalent: "")
        automaticItem.target = self
        automaticItem.representedObject = Self.automaticColorValue
        automaticItem.state = selectedProjectColorHex == nil ? .on : .off
        automaticItem.image = workspaceSidebarAutomaticColorSwatchImage(isSelected: selectedProjectColorHex == nil)
        menu.addItem(automaticItem)
    }

    var selectedProjectColorHex: String? {
        parent.projects
            .first { $0.id == parent.selectedProjectId }?
            .colorHex
            .flatMap(normalizedWorkspaceSidebarColorHex)
    }
}
