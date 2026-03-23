import Common
import Foundation

private let persistedFrozenWorldVersion = 1
private let persistedFrozenWorldFilename = "window-state.json"
@MainActor private var pendingPersistedFrozenWorld: FrozenWorld? = nil
@MainActor private var didRestorePersistedFrozenWorldDuringCurrentSession = false

private struct PersistedFrozenWorldEnvelope: Codable {
    let version: Int
    let world: FrozenWorld
}

@MainActor
private func persistedFrozenWorldUrl() throws -> URL {
    let appSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true,
    )
    let directory = appSupport.appendingPathComponent(aeroSpaceAppName, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(persistedFrozenWorldFilename, isDirectory: false)
}

@MainActor
private func currentFrozenWorld() -> FrozenWorld {
    let workspaces = Workspace.all
    return FrozenWorld(
        workspaces: workspaces.map(FrozenWorkspace.init),
        monitors: monitors.map(FrozenMonitor.init),
        windowIds: workspaces.flatMap { collectAllWindowIds(workspace: $0) }.toSet(),
    )
}

@MainActor
func persistFrozenWorldForRestartIfPossible() {
    do {
        let url = try persistedFrozenWorldUrl()
        let world = currentFrozenWorld()
        guard !world.windowIds.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let data = try JSONEncoder.aeroSpaceDefault.encode(
            PersistedFrozenWorldEnvelope(version: persistedFrozenWorldVersion, world: world),
        )
        try data.write(to: url, options: .atomic)
    } catch {
        // Best effort. Failure to save restart state must not block termination.
    }
}

@discardableResult
@MainActor
func loadPersistedFrozenWorldForStartupIfPresent() -> Bool {
    do {
        let url = try persistedFrozenWorldUrl()
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(PersistedFrozenWorldEnvelope.self, from: data)
        guard envelope.version == persistedFrozenWorldVersion else { return false }
        pendingPersistedFrozenWorld = envelope.world
        didRestorePersistedFrozenWorldDuringCurrentSession = false
        return true
    } catch {
        return false
    }
}

@MainActor
func restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: Window) async throws -> Bool {
    guard let pendingPersistedFrozenWorld else { return false }
    let didRestore = try await restoreFrozenWorldIfNeeded(pendingPersistedFrozenWorld, newlyDetectedWindow: newlyDetectedWindow)
    if didRestore {
        didRestorePersistedFrozenWorldDuringCurrentSession = true
    }
    return didRestore
}

@MainActor
func finalizePersistedFrozenWorldAfterRefresh(aliveWindowIds: Set<UInt32>) {
    guard let world = pendingPersistedFrozenWorld else { return }
    let knownWindowIds = Set(MacWindow.allWindowsMap.keys)
    if world.windowIds.isSubset(of: knownWindowIds) ||
        (didRestorePersistedFrozenWorldDuringCurrentSession &&
            !world.windowIds.isSubset(of: aliveWindowIds))
    {
        pendingPersistedFrozenWorld = nil
        didRestorePersistedFrozenWorldDuringCurrentSession = false
        try? FileManager.default.removeItem(at: persistedFrozenWorldUrl())
    }
}
