import AppKit
import Common
import DeckCore
import SwiftUI

final class WorkspaceSidebarProjectMenuControl: NSControl {
    let pillLayer = CALayer()
    let titleField = NSTextField(labelWithString: "")
    let chevronView = NSImageView()
    var isExternallyHovered = false
    var isPressed = false
    var preferredSize = NSSize(width: 92, height: workspaceSidebarPagerHeight)

    override var intrinsicContentSize: NSSize {
        preferredSize
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        pillLayer.masksToBounds = true
        layer?.addSublayer(pillLayer)

        titleField.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.backgroundColor = .clear
        titleField.isBordered = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        chevronView.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevronView.symbolConfiguration = .init(pointSize: 8.5, weight: .semibold)
        chevronView.imageScaling = .scaleProportionallyDown
        addSubview(chevronView)

        toolTip = "Projects"
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("Projects")
        update(title: "Project", width: preferredSize.width, isHovered: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return self
    }

    func update(title: String, width: CGFloat, isHovered: Bool) {
        let resolvedWidth = max(width, 1)
        let resolvedHeight = max(bounds.height, workspaceSidebarPagerHeight)
        let nextSize = NSSize(width: resolvedWidth, height: resolvedHeight)
        if preferredSize != nextSize {
            preferredSize = nextSize
            invalidateIntrinsicContentSize()
        }
        titleField.stringValue = title
        isExternallyHovered = isHovered
        updateColors()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pillHeight = min(bounds.height, 26)
        let pillFrame = CGRect(
            x: 0,
            y: (bounds.height - pillHeight) / 2,
            width: bounds.width,
            height: pillHeight,
        )
        pillLayer.frame = pillFrame
        pillLayer.cornerRadius = pillHeight / 2

        let horizontalInset: CGFloat = 10
        let chevronSize: CGFloat = 11
        let chevronGap: CGFloat = 6
        let titleMaxWidth = max(bounds.width - horizontalInset * 2 - chevronSize - chevronGap, 12)
        let titleWidth = min(ceil(titleField.intrinsicContentSize.width) + 6, titleMaxWidth)
        let titleHeight: CGFloat = 16
        titleField.frame = NSRect(
            x: pillFrame.minX + horizontalInset,
            y: pillFrame.midY - titleHeight / 2 - 0.5,
            width: titleWidth,
            height: titleHeight,
        )

        chevronView.frame = NSRect(
            x: pillFrame.maxX - horizontalInset - chevronSize,
            y: pillFrame.midY - chevronSize / 2 - 0.5,
            width: chevronSize,
            height: chevronSize,
        )
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateColors()
        sendAction(action, to: target)
        isPressed = false
        updateColors()
    }

    func updateColors() {
        let textAlpha: CGFloat = isPressed ? 0.90 : isExternallyHovered ? 0.82 : 0.72
        titleField.textColor = NSColor.white.withAlphaComponent(textAlpha)
        chevronView.contentTintColor = NSColor.white.withAlphaComponent(textAlpha)
        pillLayer.backgroundColor = NSColor.white.withAlphaComponent(isPressed ? 0.095 : 0.065).cgColor
        pillLayer.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        pillLayer.borderWidth = 0.5
    }
}

struct WorkspaceSidebarProjectMenuButton: NSViewRepresentable {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let selectedProjectName: String
    let width: CGFloat
    let isHovered: Bool
    let canDeleteSelectedProject: Bool
    let onSelectProject: (WorkspaceProjectId) -> Void
    let onCreateProject: () -> Void
    let onRenameSelectedProject: () -> Void
    let onSetSelectedProjectColor: (String?) -> Void
    let onDeleteSelectedProject: () -> Void
    let onOpenDeckProfile: (String, DeckProfileLaunchDestination) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WorkspaceSidebarProjectMenuControl {
        let control = WorkspaceSidebarProjectMenuControl()
        control.target = context.coordinator
        control.action = #selector(Coordinator.openMenu(_:))
        return control
    }

    func updateNSView(_ control: WorkspaceSidebarProjectMenuControl, context: Context) {
        context.coordinator.parent = self
        control.update(title: selectedProjectName, width: width, isHovered: isHovered)
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        private static let automaticColorValue = "__automatic__"

        var parent: WorkspaceSidebarProjectMenuButton
        var activeMenu: NSMenu?

        init(_ parent: WorkspaceSidebarProjectMenuButton) {
            self.parent = parent
        }

        @objc func openMenu(_ sender: WorkspaceSidebarProjectMenuControl) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.showsStateColumn = false
            menu.delegate = self

            for project in parent.projects {
                let item = NSMenuItem(
                    title: project.displayName,
                    action: #selector(selectProject(_:)),
                    keyEquivalent: "",
                )
                item.target = self
                item.representedObject = project.id
                menu.addItem(item)
            }

            if !parent.projects.isEmpty {
                menu.addItem(.separator())
            }

            let newItem = NSMenuItem(title: "New", action: #selector(createProject(_:)), keyEquivalent: "")
            newItem.target = self
            menu.addItem(newItem)

            addDeckProfileItems(to: menu)

            menu.update()
            let menuSize = menu.size
            let x = min(0, sender.bounds.width - menuSize.width)
            let y = sender.bounds.height + menuSize.height + 4
            activeMenu = menu
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: x, y: y),
                in: sender,
            )
        }

        func menuDidClose(_ menu: NSMenu) {
            activeMenu = nil
        }

        @objc func selectProject(_ item: NSMenuItem) {
            guard let projectId = item.representedObject as? WorkspaceProjectId else { return }
            parent.onSelectProject(projectId)
        }

        @objc func createProject(_ item: NSMenuItem) {
            parent.onCreateProject()
        }

        @objc func openDeckProfileInNewProject(_ item: NSMenuItem) {
            guard let profileName = item.representedObject as? String else { return }
            parent.onOpenDeckProfile(profileName, .newProject)
        }

        @objc func appendDeckProfileToCurrentProject(_ item: NSMenuItem) {
            guard let profileName = item.representedObject as? String else { return }
            parent.onOpenDeckProfile(profileName, .currentProject)
        }

        @objc func openDeckProfilesFolder(_ item: NSMenuItem) {
            let storage = DeckStorage()
            try? storage.ensureDirectories()
            NSWorkspace.shared.open(storage.profilesDirectory)
        }

        @objc func renameProject(_ item: NSMenuItem) {
            parent.onRenameSelectedProject()
        }

        @objc func setColor(_ item: NSMenuItem) {
            guard let value = item.representedObject as? String else { return }
            parent.onSetSelectedProjectColor(value == Self.automaticColorValue ? nil : value)
        }

        @objc func deleteProject(_ item: NSMenuItem) {
            parent.onDeleteSelectedProject()
        }

        func colorMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            let automaticItem = NSMenuItem(title: "Auto", action: #selector(setColor(_:)), keyEquivalent: "")
            automaticItem.target = self
            automaticItem.representedObject = Self.automaticColorValue
            automaticItem.state = selectedProjectColorHex == nil ? .on : .off
            automaticItem.image = workspaceSidebarAutomaticColorSwatchImage(isSelected: selectedProjectColorHex == nil)
            menu.addItem(automaticItem)

            menu.addItem(.separator())

            for preset in workspaceSidebarProjectColorPresets {
                let item = NSMenuItem(title: preset.name, action: #selector(setColor(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.hex
                item.state = selectedProjectColorHex == preset.hex ? .on : .off
                item.image = workspaceSidebarProjectColorSwatchImage(
                    hex: preset.hex,
                    isSelected: selectedProjectColorHex == preset.hex,
                )
                menu.addItem(item)
            }

            return menu
        }

        var selectedProjectColorHex: String? {
            parent.projects
                .first { $0.id == parent.selectedProjectId }?
                .colorHex
                .flatMap(normalizedWorkspaceSidebarColorHex)
        }

        func addDeckProfileItems(to menu: NSMenu) {
            let storage = DeckStorage()
            let profiles = (try? storage.listProfiles()) ?? []

            menu.addItem(.separator())

            let headerItem = NSMenuItem(title: "Project Templates", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            if profiles.isEmpty {
                let emptyItem = NSMenuItem(title: "No templates", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
            } else {
                for profile in profiles {
                    menu.addItem(deckProfileMenuItem(profile.name))
                }
            }

            let folderItem = NSMenuItem(
                title: "Open Templates Folder",
                action: #selector(openDeckProfilesFolder(_:)),
                keyEquivalent: "",
            )
            folderItem.target = self
            menu.addItem(folderItem)
        }

        func deckProfileMenuItem(_ profileName: String) -> NSMenuItem {
            let profileItem = NSMenuItem(title: profileName, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false

            let appendItem = NSMenuItem(
                title: "Append to Current Project",
                action: #selector(appendDeckProfileToCurrentProject(_:)),
                keyEquivalent: "",
            )
            appendItem.target = self
            appendItem.representedObject = profileName
            submenu.addItem(appendItem)

            let newProjectItem = NSMenuItem(
                title: "Open in New Project",
                action: #selector(openDeckProfileInNewProject(_:)),
                keyEquivalent: "",
            )
            newProjectItem.target = self
            newProjectItem.representedObject = profileName
            submenu.addItem(newProjectItem)

            profileItem.submenu = submenu
            return profileItem
        }
    }
}

struct WorkspaceSidebarProjectRenameField: NSViewRepresentable {
    @Binding var text: String
    let focusId: String
    let alignment: NSTextAlignment
    let fontSize: CGFloat
    let fontWeight: NSFont.Weight
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WorkspaceSidebarRenameTextField {
        let field = WorkspaceSidebarRenameTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        return field
    }

    func updateNSView(_ field: WorkspaceSidebarRenameTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
        context.coordinator.field = field
        context.coordinator.installOutsideInteractionMonitor(for: field)
        field.onCommit = {
            context.coordinator.commit()
        }
        field.onCancel = {
            context.coordinator.cancel()
        }
        field.alignment = alignment
        field.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        field.textColor = .white
        if field.stringValue != text {
            field.stringValue = text
        }
        guard context.coordinator.focusId != focusId else { return }
        context.coordinator.focusId = focusId
        context.coordinator.didResolve = false
        DispatchQueue.main.async {
            WorkspaceSidebarPanel.shared.prepareForInlineTextEditing()
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    static func dismantleNSView(_ field: WorkspaceSidebarRenameTextField, coordinator: Coordinator) {
        coordinator.removeOutsideInteractionMonitor()
        field.onCommit = nil
        field.onCancel = nil
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: WorkspaceSidebarProjectRenameField
        var focusId: String?
        var didResolve = false
        var onCommit: (() -> Void)?
        var onCancel: (() -> Void)?
        weak var field: WorkspaceSidebarRenameTextField?
        var outsideInteractionMonitor: Any?

        init(_ parent: WorkspaceSidebarProjectRenameField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func installOutsideInteractionMonitor(for field: WorkspaceSidebarRenameTextField) {
            guard outsideInteractionMonitor == nil else { return }
            outsideInteractionMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
            ) { [weak self, weak field] event in
                guard let self, let field else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.cancel()
                    return nil
                }
                if event.type == .keyDown {
                    return event
                }
                guard event.window === field.window else {
                    self.commit()
                    return event
                }
                let localPoint = field.convert(event.locationInWindow, from: nil)
                if !field.bounds.contains(localPoint) {
                    self.commit()
                }
                return event
            }
        }

        func removeOutsideInteractionMonitor() {
            if let outsideInteractionMonitor {
                NSEvent.removeMonitor(outsideInteractionMonitor)
                self.outsideInteractionMonitor = nil
            }
        }

        func commit() {
            guard !didResolve else { return }
            didResolve = true
            if let field {
                parent.text = field.stringValue
                field.window?.makeFirstResponder(nil)
            }
            removeOutsideInteractionMonitor()
            onCommit?()
        }

        func cancel() {
            guard !didResolve else { return }
            didResolve = true
            field?.window?.makeFirstResponder(nil)
            removeOutsideInteractionMonitor()
            onCancel?()
        }
    }
}

final class WorkspaceSidebarRenameTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
            case 36, 76:
                onCommit?()
            case 53:
                onCancel?()
            default:
                super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignFirstResponder() -> Bool {
        super.resignFirstResponder()
    }
}
