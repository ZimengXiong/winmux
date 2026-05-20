import AppKit
import CoreGraphics

enum WorkspaceSidebarInlineTextKey {
    case text(String)
    case deleteBackward
    case deleteForward
    case commit
    case cancel
    case ignored
}

private let workspaceSidebarInlineTextEventTapCallback: CGEventTapCallBack = { _, type, event, _ in
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    let key = workspaceSidebarInlineTextKey(from: event)
    DispatchQueue.main.async {
        _ = WorkspaceSidebarPanel.shared.handleInlineTextEditingKey(key)
    }
    return nil
}

private func workspaceSidebarInlineTextKey(from event: CGEvent) -> WorkspaceSidebarInlineTextKey {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    switch keyCode {
        case 36, 76:
            return .commit
        case 53:
            return .cancel
        case 51:
            return .deleteBackward
        case 117:
            return .deleteForward
        default:
            break
    }

    var length = 0
    var chars = [UniChar](repeating: 0, count: 8)
    event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
    guard length > 0 else { return .ignored }
    let text = String(utf16CodeUnits: chars, count: length)
    guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        return .ignored
    }
    return text.isEmpty ? .ignored : .text(text)
}

extension WorkspaceSidebarPanel {
    func beginInlineTextEditing(
        onCancel: (@MainActor () -> Void)? = nil,
        onKeyDown: (@MainActor (WorkspaceSidebarInlineTextKey) -> Void)? = nil
    ) {
        debugWorkspaceSidebarRenameLog("beginInlineTextEditing isKeyBefore=\(isKeyWindow) firstResponder=\(String(describing: firstResponder)) mouseInside=\(isMouseInsideVisibleRegion())")
        inlineTextEditingActive = true
        inlineTextEditingCancel = onCancel
        inlineTextEditingKeyDown = onKeyDown
        inlineTextEditingStartedAt = .now
        inlineTextEditingPointerEnteredVisibleRegion = isMouseInsideVisibleRegion()
        prepareForInlineTextEditing()
        installInlineTextEditingEventMonitors()
        installInlineTextEditingKeyEventTap()
    }

    func endInlineTextEditing() {
        guard inlineTextEditingActive else { return }
        debugWorkspaceSidebarRenameLog("endInlineTextEditing isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
        inlineTextEditingActive = false
        inlineTextEditingCancel = nil
        inlineTextEditingKeyDown = nil
        inlineTextEditingPointerEnteredVisibleRegion = false
        removeInlineTextEditingEventMonitors()
        removeInlineTextEditingKeyEventTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
    }

    func prepareForInlineTextEditing() {
        debugWorkspaceSidebarRenameLog("prepareForInlineTextEditing before visible=\(isVisible) isKey=\(isKeyWindow) ignoresMouse=\(ignoresMouseEvents) firstResponder=\(String(describing: firstResponder))")
        cancelExpansionWork()
        expandSidebar(to: CGFloat(config.workspaceSidebar.width))
        ignoresMouseEvents = false
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
        debugWorkspaceSidebarRenameLog("prepareForInlineTextEditing after visible=\(isVisible) isKey=\(isKeyWindow) ignoresMouse=\(ignoresMouseEvents) firstResponder=\(String(describing: firstResponder)) activeApp=\(NSApp.isActive)")
    }

    func cancelInlineTextEditing() {
        guard inlineTextEditingActive else { return }
        debugWorkspaceSidebarRenameLog("cancelInlineTextEditing isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
        inlineTextEditingCancel?()
    }

    func handleInlineTextEditingKey(_ key: WorkspaceSidebarInlineTextKey) -> Bool {
        guard inlineTextEditingActive, let inlineTextEditingKeyDown else { return false }
        debugWorkspaceSidebarRenameLog("handleInlineTextEditingKey key=\(key)")
        inlineTextEditingKeyDown(key)
        if case .ignored = key {
            return false
        }
        return true
    }

    func shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: Bool) -> Bool {
        if isMouseInsideVisibleRegion() {
            inlineTextEditingPointerEnteredVisibleRegion = true
            return false
        }
        if inlineTextEditingPointerEnteredVisibleRegion {
            debugWorkspaceSidebarRenameLog("outsidePointerCancel afterEntered isMouseDown=\(isMouseDown)")
            return true
        }
        let shouldCancel = isMouseDown && Date().timeIntervalSince(inlineTextEditingStartedAt) > 0.25
        if shouldCancel {
            debugWorkspaceSidebarRenameLog("outsidePointerCancel clickGraceElapsed")
        }
        return shouldCancel
    }

    func installInlineTextEditingEventMonitors() {
        removeInlineTextEditingEventMonitors()
        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let localMouseDown = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            guard let self else { return event }
            if !self.isEventInsideVisibleRegion(event),
               self.shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: true)
            {
                Task { @MainActor in self.cancelInlineTextEditing() }
            }
            return event
        }
        let localMouseMove = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            guard let self else { return event }
            if self.shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: false) {
                Task { @MainActor in self.cancelInlineTextEditing() }
            }
            return event
        }
        let globalMouseDown = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if !self.isScreenPointInsideVisibleRegion(event.locationInWindow),
                   self.shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: true)
                {
                    self.cancelInlineTextEditing()
                }
            }
        }
        let globalMouseMove = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.shouldCancelInlineTextEditingForOutsidePointer(isMouseDown: false) {
                    self.cancelInlineTextEditing()
                }
            }
        }
        inlineTextEditingEventMonitors = [localMouseDown, localMouseMove, globalMouseDown, globalMouseMove].compactMap { $0 }
    }

    func removeInlineTextEditingEventMonitors() {
        for monitor in inlineTextEditingEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        inlineTextEditingEventMonitors = []
    }

    func installInlineTextEditingKeyEventTap() {
        removeInlineTextEditingKeyEventTap()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: workspaceSidebarInlineTextEventTapCallback,
            userInfo: nil
        ) else {
            debugWorkspaceSidebarRenameLog("installKeyEventTap failed")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            debugWorkspaceSidebarRenameLog("installKeyEventTap source failed")
            return
        }
        inlineTextEditingKeyEventTap = tap
        inlineTextEditingKeyEventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        debugWorkspaceSidebarRenameLog("installKeyEventTap ok")
    }

    func removeInlineTextEditingKeyEventTap() {
        if let source = inlineTextEditingKeyEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = inlineTextEditingKeyEventTap {
            CFMachPortInvalidate(tap)
        }
        inlineTextEditingKeyEventTap = nil
        inlineTextEditingKeyEventTapRunLoopSource = nil
    }

    func isEventInsideVisibleRegion(_ event: NSEvent) -> Bool {
        guard event.window === self else { return false }
        let point = convertPoint(toScreen: event.locationInWindow)
        return isScreenPointInsideVisibleRegion(point)
    }

    func isScreenPointInsideVisibleRegion(_ point: CGPoint) -> Bool {
        guard isVisible else { return false }
        let visibleRegion = NSRect(
            x: frame.minX,
            y: frame.minY,
            width: viewModel.workspaceSidebarVisibleWidth,
            height: frame.height,
        )
        return visibleRegion.contains(point)
    }
}
