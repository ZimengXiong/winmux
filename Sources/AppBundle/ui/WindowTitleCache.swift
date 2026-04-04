import Foundation

private struct CachedWindowTitle {
    let title: String?
    let fetchedAt: Date
}

private let cachedWindowTitleMaxAge: TimeInterval = 1

@MainActor
private var cachedWindowTitles: [UInt32: CachedWindowTitle] = [:]

@MainActor
func resetCachedWindowTitles() {
    cachedWindowTitles = [:]
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
