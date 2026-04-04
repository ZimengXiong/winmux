import Common

extension Workspace {
    private func existingContainer<T: TreeNode>(_ type: T.Type) -> T? {
        let containers = children.filterIsInstance(of: T.self)
        return switch containers.count {
            case 0: nil
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one \(T.self)")
        }
    }

    @MainActor var rootTilingContainer: TilingContainer {
        let containers = children.filterIsInstance(of: TilingContainer.self)
        switch containers.count {
            case 0:
                let orientation: Orientation = switch config.defaultRootContainerOrientation {
                    case .horizontal: .h
                    case .vertical: .v
                    case .auto: workspaceMonitor.then { $0.width >= $0.height } ? .h : .v
                }
                return TilingContainer(parent: self, adaptiveWeight: 1, orientation, config.defaultRootContainerLayout, index: INDEX_BIND_LAST)
            case 1:
                return containers.singleOrNil().orDie()
            default:
                die("Workspace must contain zero or one tiling container as its child")
        }
    }

    var floatingWindows: [Window] {
        children.filterIsInstance(of: Window.self)
    }

    var existingMacOsNativeFullscreenWindowsContainer: MacosFullscreenWindowsContainer? {
        existingContainer(MacosFullscreenWindowsContainer.self)
    }

    @MainActor var macOsNativeFullscreenWindowsContainer: MacosFullscreenWindowsContainer {
        existingMacOsNativeFullscreenWindowsContainer ?? MacosFullscreenWindowsContainer(parent: self)
    }

    var existingMacOsNativeHiddenAppsWindowsContainer: MacosHiddenAppsWindowsContainer? {
        existingContainer(MacosHiddenAppsWindowsContainer.self)
    }

    @MainActor var macOsNativeHiddenAppsWindowsContainer: MacosHiddenAppsWindowsContainer {
        existingMacOsNativeHiddenAppsWindowsContainer ?? MacosHiddenAppsWindowsContainer(parent: self)
    }

    @MainActor var forceAssignedMonitor: Monitor? { nil }
}
