import Foundation

private struct CachedWindowTitle {
    let title: String?
    let fetchedAt: Date
}

private let cachedWindowTitleMaxAge: TimeInterval = 5

@MainActor
private var cachedWindowTitles: [UInt32: CachedWindowTitle] = [:]

@MainActor
private var pendingTitleRefreshWindowIds: Set<UInt32> = []

@MainActor
private var backgroundTitleRefreshTask: Task<Void, Never>? = nil

@MainActor
func resetCachedWindowTitles() {
    cachedWindowTitles = [:]
    pendingTitleRefreshWindowIds = []
    backgroundTitleRefreshTask?.cancel()
    backgroundTitleRefreshTask = nil
}

@MainActor
func cachedWindowTitle(for window: Window) -> String? {
    cachedWindowTitles[window.windowId]?.title
}

@MainActor
func pruneCachedWindowTitles() {
    cachedWindowTitles = cachedWindowTitles.filter { Window.get(byId: $0.key) != nil }
}

@MainActor
func getCachedWindowTitle(
    _ window: Window,
    maxAge: TimeInterval = cachedWindowTitleMaxAge,
    now: Date = .now,
) async -> String? {
    if let cached = cachedWindowTitles[window.windowId],
       now.timeIntervalSince(cached.fetchedAt) < maxAge
    {
        return cached.title
    }

    let cachedTitle = cachedWindowTitles[window.windowId]?.title
    let rawTitle = try? await window.title
    let normalized = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).takeIf { !$0.isEmpty }
    let refreshedTitle = normalized ?? cachedTitle
    cachedWindowTitles[window.windowId] = CachedWindowTitle(title: refreshedTitle, fetchedAt: now)
    return refreshedTitle
}

/// Title accessor for the per-session UI model builders (sidebar rows, tab strips).
///
/// A known window's title is returned from the cache immediately — even when the entry is past
/// its TTL — and the stale entry is queued for a background refresh instead. Refreshing inline
/// used to serialize one AX round-trip per stale window inside every refresh session, which is
/// exactly when the target apps are busiest. A window seen for the first time is still fetched
/// inline so its first paint shows the real title rather than a placeholder.
///
/// When the background refresh finds any title actually changed, it re-runs the sidebar and tab
/// model updates; those are equality-guarded, so an unchanged title costs nothing.
@MainActor
func getSessionWindowTitle(_ window: Window, now: Date = .now) async -> String? {
    if let cached = cachedWindowTitles[window.windowId] {
        if now.timeIntervalSince(cached.fetchedAt) >= cachedWindowTitleMaxAge {
            scheduleBackgroundWindowTitleRefresh(windowId: window.windowId)
        }
        return cached.title
    }
    return await getCachedWindowTitle(window, now: now)
}

@MainActor
private func scheduleBackgroundWindowTitleRefresh(windowId: UInt32) {
    pendingTitleRefreshWindowIds.insert(windowId)
    guard backgroundTitleRefreshTask == nil else { return }
    backgroundTitleRefreshTask = Task { @MainActor in
        var didAnyTitleChange = false
        while !pendingTitleRefreshWindowIds.isEmpty, !Task.isCancelled {
            let batch = pendingTitleRefreshWindowIds
            pendingTitleRefreshWindowIds = []
            await withTaskGroup(of: Bool.self) { group in
                for windowId in batch {
                    guard let window = Window.get(byId: windowId) else { continue }
                    group.addTask { @Sendable @MainActor in
                        let before = cachedWindowTitle(for: window)
                        let after = await getCachedWindowTitle(window)
                        return before != after
                    }
                }
                for await changed in group where changed {
                    didAnyTitleChange = true
                }
            }
        }
        // When cancelled, resetCachedWindowTitles already cleared (or replaced) the handle;
        // nilling it here would clobber a successor task's handle and break single-flight.
        if Task.isCancelled { return }
        backgroundTitleRefreshTask = nil
        if didAnyTitleChange {
            await updateWorkspaceSidebarModel()
            await updateWindowTabModel()
        }
    }
}
