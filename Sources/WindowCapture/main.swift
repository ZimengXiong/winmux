import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

private enum CaptureError: LocalizedError {
    case noMatchingWindow(String, availableTitles: [String])
    case applicationNotFound(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
            case let .noMatchingWindow(bundleIdentifier, availableTitles):
                "No matching visible window belongs to \(bundleIdentifier). Available windows: \(availableTitles.joined(separator: ", "))."
            case let .applicationNotFound(bundleIdentifier):
                "No installed application has the bundle identifier \(bundleIdentifier)."
            case .encodingFailed:
                "AppKit could not encode the captured window as PNG."
        }
    }
}

@main
private struct WindowCaptureCommand {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let outputPath = arguments.first ?? "resources/marketing/captures/safari-retina.png"
        let bundleIdentifier = arguments.dropFirst().first ?? "com.apple.Safari"
        let rawTitleFilter = arguments.dropFirst(2).first(where: { !$0.hasPrefix("--") })
        let titleFilter = rawTitleFilter.flatMap { $0.isEmpty ? nil : $0 }
        let useCoreGraphics = arguments.contains("--core-graphics")
        let requestedURL = value(after: "--url", in: arguments).flatMap(URL.init(string:))
        let settleMilliseconds = value(after: "--settle-ms", in: arguments).flatMap(UInt64.init) ?? 1_500
        let outputURL = URL(
            fileURLWithPath: outputPath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL

        guard #available(macOS 14.0, *) else {
            fatalError("High-resolution window capture requires macOS 14 or newer.")
        }

        await MainActor.run {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            if !application.isRunning {
                application.finishLaunching()
            }
        }

        if let requestedURL {
            try await open(
                requestedURL,
                withApplicationIdentifier: bundleIdentifier,
                settleMilliseconds: settleMilliseconds
            )
        }

        if useCoreGraphics {
            try await captureUsingCoreGraphics(
                bundleIdentifier: bundleIdentifier,
                titleFilter: titleFilter,
                outputURL: outputURL
            )
            return
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        guard let window = content.windows
            .filter({ $0.owningApplication?.bundleIdentifier == bundleIdentifier })
            .filter({ $0.frame.width >= 400 && $0.frame.height >= 300 })
            .filter({ window in
                guard let titleFilter else { return true }
                return window.title?.localizedCaseInsensitiveContains(titleFilter) == true
            })
            .max(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) })
        else {
            let availableTitles = content.windows
                .filter({ $0.owningApplication?.bundleIdentifier == bundleIdentifier })
                .compactMap(\.title)
            throw CaptureError.noMatchingWindow(bundleIdentifier, availableTitles: availableTitles)
        }

        if let processIdentifier = window.owningApplication?.processID,
           let runningApplication = NSRunningApplication(processIdentifier: processIdentifier)
        {
            runningApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            try await Task.sleep(for: .milliseconds(700))
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width.rounded(.up)) * 2
        configuration.height = Int(window.frame.height.rounded(.up)) * 2
        configuration.captureResolution = .best
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
            throw CaptureError.encodingFailed
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        print("Captured \(window.title ?? bundleIdentifier) at \(image.width)x\(image.height)")
        print(outputURL.path)
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    @MainActor
    private static func open(
        _ url: URL,
        withApplicationIdentifier bundleIdentifier: String,
        settleMilliseconds: UInt64
    ) async throws {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            throw CaptureError.applicationNotFound(bundleIdentifier)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        try await Task.sleep(for: .milliseconds(settleMilliseconds))
    }

    private static func captureUsingCoreGraphics(
        bundleIdentifier: String,
        titleFilter: String?,
        outputURL: URL
    ) async throws {
        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let candidates = windowInfo.compactMap { information -> (id: CGWindowID, title: String, pid: pid_t, area: CGFloat)? in
            guard let processIdentifier = information[kCGWindowOwnerPID as String] as? pid_t,
                  let application = NSRunningApplication(processIdentifier: processIdentifier),
                  application.bundleIdentifier == bundleIdentifier,
                  let number = information[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDictionary = information[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 400,
                  bounds.height >= 300
            else { return nil }

            let title = information[kCGWindowName as String] as? String ?? ""
            if let titleFilter,
               !title.localizedCaseInsensitiveContains(titleFilter)
            {
                return nil
            }
            return (number, title, processIdentifier, bounds.width * bounds.height)
        }

        guard let window = candidates.max(by: { $0.area < $1.area }) else {
            let availableTitles = windowInfo.compactMap { information -> String? in
                guard let processIdentifier = information[kCGWindowOwnerPID as String] as? pid_t,
                      NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier == bundleIdentifier
                else { return nil }
                return information[kCGWindowName as String] as? String
            }
            throw CaptureError.noMatchingWindow(bundleIdentifier, availableTitles: availableTitles)
        }

        if let application = NSRunningApplication(processIdentifier: window.pid) {
            application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            try await Task.sleep(for: .milliseconds(150))
            focusWindow(processIdentifier: window.pid, title: window.title)
            try await Task.sleep(for: .milliseconds(700))
        }

        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            window.id,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw CaptureError.encodingFailed
        }
        try write(image, to: outputURL)
        print("Captured \(window.title.isEmpty ? bundleIdentifier : window.title) at \(image.width)x\(image.height) with Core Graphics")
        print(outputURL.path)
    }

    private static func focusWindow(processIdentifier: pid_t, title: String) {
        guard !title.isEmpty else { return }

        let application = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let windows = windowsValue as? [AXUIElement]
        else { return }

        for window in windows {
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXTitleAttribute as CFString,
                &titleValue
            ) == .success,
                  let candidateTitle = titleValue as? String,
                  candidateTitle.localizedCaseInsensitiveCompare(title) == .orderedSame
            else { continue }

            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return
        }
    }

    private static func write(_ image: CGImage, to outputURL: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
            throw CaptureError.encodingFailed
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }
}
