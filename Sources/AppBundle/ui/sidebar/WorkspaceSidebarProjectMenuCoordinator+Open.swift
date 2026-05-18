import AppKit

extension WorkspaceSidebarProjectMenuCoordinator {
    @objc func openMenu(_ sender: WorkspaceSidebarProjectMenuControl) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.showsStateColumn = false
        menu.delegate = self
        addProjectItems(to: menu)
        addNewItem(to: menu)

        menu.update()
        let menuSize = menu.size
        let x = min(0, sender.bounds.width - menuSize.width)
        let y = sender.bounds.height + menuSize.height + 4
        activeMenu = menu
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: sender)
    }

    private func addProjectItems(to menu: NSMenu) {
        for project in parent.projects {
            let item = NSMenuItem(title: project.displayName, action: #selector(selectProject(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = project.id
            menu.addItem(item)
        }
        if !parent.projects.isEmpty {
            menu.addItem(.separator())
        }
    }

    private func addNewItem(to menu: NSMenu) {
        let newItem = NSMenuItem(title: "New", action: #selector(createProject(_:)), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)
    }
}
