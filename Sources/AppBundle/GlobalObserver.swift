import AppKit
import Common

enum GlobalObserver {
    @MainActor private static var isInitialized = false
    @MainActor private static var notificationObserverTokens: [NSObjectProtocol] = []
    @MainActor private static var eventMonitorTokens: [Any] = []

    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == lockScreenAppBundleId {
            return
        }
        let notifName = notification.name.rawValue
        Task { @MainActor in
            if !TrayMenuModel.shared.isEnabled { return }
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                scheduleRefreshSession(.globalObserver(notifName), optimisticallyPreLayoutWorkspaces: true)
            } else {
                scheduleRefreshSession(.globalObserver(notifName))
            }
        }
    }

    private static func onHideApp(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.globalObserver(notifName), token) {
                if config.automaticallyUnhideMacosHiddenApps {
                    if let w = prevFocus?.windowOrNil,
                       w.macAppUnsafe.nsApp.isHidden,
                       // "Hide others" (cmd-alt-h) -> don't force focus
                       // "Hide app" (cmd-h) -> force focus
                       MacApp.allAppsMap.values.count(where: { $0.nsApp.isHidden }) == 1
                    {
                        // Force focus
                        _ = w.focusWindow()
                        w.nativeFocus()
                    }
                    for app in MacApp.allAppsMap.values {
                        app.nsApp.unhide()
                    }
                }
            }
        }
    }

    private static func onKeyDown(_ event: NSEvent) {
        let modifierFlags = event.modifierFlags
        let keyCode = event.keyCode
        Task { @MainActor in
            noteTapBindingKeyDown()
            if modifierFlags.contains(.control), keyCode == 34 { // 'i' key
                ExposePanel.shared.toggle()
            }
        }
    }

    private static func onFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        Task { @MainActor in
            noteTapBindingFlagsChanged(keyCode: keyCode, modifierFlags: modifierFlags)
        }
    }

    private static func onPointerActivity(_: NSEvent) {
        Task { @MainActor in
            noteTapBindingKeyDown()
        }
    }

    @MainActor
    static func initObserver() {
        guard !isInitialized else { return }
        isInitialized = true

        let nc = NSWorkspace.shared.notificationCenter
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif))

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            // todo reduce number of refreshSession in the callback
            //  resetManipulatedWithMouseIfPossible might call its own refreshSession
            //  The end of the callback calls refreshSession
            Task { @MainActor in
                guard let token: RunSessionGuard = .isServerEnabled else { return }
                try await resetManipulatedWithMouseIfPossible()
                let mouseLocation = mouseLocation
                let clickedMonitor = mouseLocation.monitorApproximation
                switch true {
                    // Detect clicks on desktop of different monitors
                    case clickedMonitor.activeWorkspace != focus.workspace:
                        _ = try await runLightSession(.globalObserverLeftMouseUp, token) {
                            clickedMonitor.activeWorkspace.focusWorkspace()
                        }
                    // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                    //  And trigger new window detection that could be delayed due to mouseDown event
                    default:
                        scheduleRefreshSession(.globalObserverLeftMouseUp)
                }
            }
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            Task { @MainActor in
                refreshPendingWindowDragIntentFromGlobalMouseDrag()
            }
        })

        let pointerActivityMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]
        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: pointerActivityMask, handler: onPointerActivity))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: pointerActivityMask) { event in
            onPointerActivity(event)
            return event
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: onFlagsChanged))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            onFlagsChanged(event)
            return event
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: onKeyDown))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            onKeyDown(event)
            if event.modifierFlags.contains(.control), event.keyCode == 34 {
                return nil // consume the event
            }
            return event
        })
    }

    @MainActor private static func retainEventMonitor(_ monitor: Any?) {
        guard let monitor else { return }
        eventMonitorTokens.append(monitor)
    }
}
