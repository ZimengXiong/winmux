import AppKit

@MainActor
private var appIconCache: [String: NSImage] = [:]

@MainActor
func appIconImage(bundleIdentifier: String?, bundlePath: String?) -> NSImage? {
    let cacheKey = bundlePath ?? bundleIdentifier ?? ""
    guard !cacheKey.isEmpty else { return nil }
    if let cached = appIconCache[cacheKey] {
        return cached
    }

    let icon: NSImage?
    if let bundlePath, !bundlePath.isEmpty {
        icon = NSWorkspace.shared.icon(forFile: bundlePath)
    } else if let bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    {
        icon = NSWorkspace.shared.icon(forFile: appURL.path)
    } else {
        icon = nil
    }

    guard let icon else { return nil }
    icon.isTemplate = false
    appIconCache[cacheKey] = icon
    return icon
}
