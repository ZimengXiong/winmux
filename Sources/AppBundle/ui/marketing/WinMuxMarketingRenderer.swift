import AppKit
import SwiftUI

/// Exports a deterministic marketing composition that embeds WinMux's production SwiftUI views.
/// The renderer does not capture the screen or read pixels from application windows.
@MainActor
public func renderWinMuxMarketingImage(to outputURL: URL) throws {
    let size = CGSize(width: 1_600, height: 900)
    let content = WinMuxMarketingCanvas()
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)

    // Liquid Glass is composed by WindowServer. A detached NSHostingView cannot reproduce the
    // material: SwiftUI.ImageRenderer omits AppKit-backed surfaces, and cacheDisplay has no live
    // compositor. Host the code-defined scene in a dedicated window, wait for composition, then
    // read only that window's surface. No existing app window or desktop content is captured.
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    if !application.isRunning {
        application.finishLaunching()
    }

    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.backgroundColor = .black
    window.isOpaque = true
    window.hasShadow = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.sharingType = .readOnly

    if let screenFrame = NSScreen.main?.visibleFrame {
        window.setFrameOrigin(CGPoint(
            x: screenFrame.midX - (size.width / 2),
            y: screenFrame.midY - (size.height / 2)
        ))
    }

    window.orderFrontRegardless()
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))

    let windowNumber = CGWindowID(window.windowNumber)
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        windowNumber,
        [.boundsIgnoreFraming, .bestResolution]
    ) else {
        window.orderOut(nil)
        throw WinMuxMarketingRenderError.renderFailed
    }

    window.orderOut(nil)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
        throw WinMuxMarketingRenderError.encodingFailed
    }
    try data.write(to: outputURL, options: .atomic)
}

private enum WinMuxMarketingRenderError: LocalizedError {
    case renderFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
            case .renderFailed:
                "SwiftUI did not produce a rendered image."
            case .encodingFailed:
                "AppKit could not encode the rendered image as PNG."
        }
    }
}

private struct WinMuxMarketingCanvas: View {
    private let sidebarSnapshot = MarketingFixtures.sidebarSnapshot
    private let codeTabs = MarketingFixtures.codeTabStrip
    private let browserTabs = MarketingFixtures.browserTabStrip

    var body: some View {
        ZStack(alignment: .topLeading) {
            MarketingDesktopWallpaper()

            MarketingMenuBar()
                .frame(height: 28)

            WorkspaceSidebarView(snapshot: sidebarSnapshot)
                .frame(width: sidebarSnapshot.visibleWidth, height: 878)
                .offset(y: 28)
                .zIndex(5)

            MarketingCapturedTabWindow(strip: codeTabs, imageName: "xcode-winmux.png")
                .frame(width: 590, height: 620)
                .offset(x: 300, y: 72)
                .rotationEffect(.degrees(-0.6))
                .zIndex(2)

            MarketingCapturedTabWindow(strip: browserTabs, imageName: "safari-swiftui.png")
                .frame(width: 735, height: 500)
                .offset(x: 820, y: 104)
                .rotationEffect(.degrees(0.45))
                .zIndex(3)

            MarketingCapturedWindow(imageName: "finder-winmux.png")
                .frame(width: 390, height: 260)
                .offset(x: 390, y: 612)
                .rotationEffect(.degrees(-1.1))
                .zIndex(3.2)

            campaignCopy
                .frame(width: 700, alignment: .leading)
                .offset(x: 835, y: 655)
                .zIndex(4)
        }
        .clipped()
    }

    private var campaignCopy: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                MarketingAppIcon()
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.42), radius: 14, y: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text("WinMux")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("A sidebar-first window manager for macOS")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                }
            }

            Text("Your workspace, in flow.")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .tracking(-1.2)

            HStack(spacing: 10) {
                MarketingFeaturePill(symbol: "sidebar.left", title: "See every space")
                MarketingFeaturePill(symbol: "rectangle.3.group", title: "Group any window")
                MarketingFeaturePill(symbol: "arrow.up.left.and.arrow.down.right", title: "Drag to arrange")
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.44))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.30), radius: 24, y: 12)
    }
}

private enum MarketingAsset {
    static func image(named name: String) -> NSImage? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return NSImage(contentsOf: root.appendingPathComponent("resources/marketing/captures/\(name)"))
    }
}

private struct MarketingDesktopWallpaper: View {
    var body: some View {
        ZStack {
            if let wallpaper = MarketingAsset.image(named: "macos-sonoma-wallpaper.png") {
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(red: 0.12, green: 0.18, blue: 0.42)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.06), Color.black.opacity(0.30)],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.16), location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: Color.black.opacity(0.10), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .frame(width: 1_600, height: 900)
        .clipped()
    }
}

private struct MarketingMenuBar: View {
    private var clockText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d  h:mm a"
        return formatter.string(from: Date())
    }

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
                .font(.system(size: 13, weight: .semibold))
            Text("WinMux").fontWeight(.semibold)
            Text("File")
            Text("Edit")
            Text("View")
            Text("Window")
            Text("Help")
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.100percent")
            Text(clockText)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
        }
    }
}

/// Wraps a real application-window capture with WinMux's production tab-group chrome.
private struct MarketingCapturedTabWindow: View {
    let strip: WindowTabStripViewModel
    let imageName: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: strip.activeWindowCornerRadius, style: .continuous)
                    .fill(Color(red: 0.035, green: 0.038, blue: 0.052))

                if let image = MarketingAsset.image(named: imageName) {
                    let scale = max(
                        proxy.size.width / max(image.size.width, 1),
                        proxy.size.height / max(image.size.height, 1)
                    )
                    let scaledHeight = image.size.height * scale
                    let topAlignmentOffset = max((scaledHeight - proxy.size.height) / 2, 0)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .offset(y: topAlignmentOffset)
                        .frame(
                            width: proxy.size.width,
                            height: max(proxy.size.height - strip.frame.height, 0)
                        )
                        .clipped()
                        .offset(y: strip.frame.height)
                }

                WindowTabGroupFrameView(strip: strip, groupSize: proxy.size)
                WindowTabStripView(strip: strip)
                    .frame(height: strip.frame.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: strip.activeWindowCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: strip.activeWindowCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.50), radius: 28, y: 17)
        }
    }
}

private struct MarketingCapturedWindow: View {
    let imageName: String

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image = MarketingAsset.image(named: imageName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(red: 0.035, green: 0.038, blue: 0.052)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.48), radius: 25, y: 15)
        }
    }
}

private struct MarketingFeaturePill: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.86))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.white.opacity(0.10), in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5) }
    }
}

private struct MarketingBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.020, blue: 0.045),
                    Color(red: 0.025, green: 0.022, blue: 0.070),
                    Color(red: 0.012, green: 0.014, blue: 0.030),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.18, green: 0.12, blue: 0.72).opacity(0.28))
                .frame(width: 820, height: 820)
                .blur(radius: 120)
                .offset(x: 410, y: -170)

            Circle()
                .fill(Color(red: 0.10, green: 0.28, blue: 0.72).opacity(0.17))
                .frame(width: 690, height: 690)
                .blur(radius: 150)
                .offset(x: 540, y: 330)
        }
    }
}

private struct MarketingAppIcon: View {
    private struct Pane: Identifiable {
        let id: Int
        let color: Color
        let size: CGSize
        let offset: CGSize
        let rotation: Angle
    }

    private let panes = [
        Pane(id: 0, color: Color(red: 0.12, green: 0.52, blue: 0.95), size: CGSize(width: 35, height: 29), offset: CGSize(width: -5, height: -16), rotation: .degrees(-9)),
        Pane(id: 1, color: Color(red: 0.92, green: 0.57, blue: 0.05), size: CGSize(width: 31, height: 32), offset: CGSize(width: 18, height: -15), rotation: .degrees(10)),
        Pane(id: 2, color: Color(red: 0.47, green: 0.27, blue: 0.70), size: CGSize(width: 29, height: 23), offset: CGSize(width: -22, height: 0), rotation: .degrees(-7)),
        Pane(id: 3, color: Color(red: 0.14, green: 0.56, blue: 0.31), size: CGSize(width: 37, height: 29), offset: CGSize(width: -8, height: 19), rotation: .degrees(8)),
        Pane(id: 4, color: Color(red: 0.78, green: 0.08, blue: 0.66), size: CGSize(width: 28, height: 27), offset: CGSize(width: 20, height: 18), rotation: .degrees(-8)),
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.10), Color.black.opacity(0.98)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 110
                    )
                )

            ForEach(panes) { pane in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [pane.color.opacity(0.72), pane.color.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(pane.color.opacity(0.85), lineWidth: 0.8)
                    }
                    .frame(width: pane.size.width, height: pane.size.height)
                    .rotationEffect(pane.rotation)
                    .offset(pane.offset)
            }

            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private enum MarketingWindowKind {
    case code
    case browser
}

/// Uses the production tab-group shell and tab-strip views around synthetic window content.
private struct MarketingTabWindow: View {
    let strip: WindowTabStripViewModel
    let kind: MarketingWindowKind
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: strip.activeWindowCornerRadius, style: .continuous)
                    .fill(Color(red: 0.055, green: 0.060, blue: 0.082))

                Group {
                    switch kind {
                        case .code:
                            MarketingCodeContent(accent: accent)
                        case .browser:
                            MarketingBrowserContent(accent: accent)
                    }
                }
                .padding(.top, strip.frame.height)
                .clipShape(RoundedRectangle(cornerRadius: strip.activeWindowCornerRadius, style: .continuous))

                WindowTabGroupFrameView(strip: strip, groupSize: proxy.size)
                WindowTabStripView(strip: strip)
                    .frame(height: strip.frame.height)
            }
        }
    }
}

private struct MarketingCodeContent: View {
    let accent: Color

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Label("winmux", systemImage: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                ForEach(["AppBundle", "ui", "sidebar", "tabs", "MarketingRenderer.swift"], id: \.self) { item in
                    Text(item)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(item.hasSuffix(".swift") ? accent : Color.white.opacity(0.42))
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 128, alignment: .leading)
            .background(Color.black.opacity(0.20))

            VStack(alignment: .leading, spacing: 9) {
                Text("WorkspaceSidebarView.swift")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
                Divider().overlay(Color.white.opacity(0.07))
                CodeLine(number: 12, segments: [("struct", .pink), (" WorkspaceSidebarView", .cyan), (": View {", .white)])
                CodeLine(number: 13, segments: [("    let", .pink), (" snapshot", .cyan), (": WorkspaceSidebarSnapshot", .white)])
                CodeLine(number: 14, segments: [("    let", .pink), (" actions", .cyan), (": WorkspaceSidebarActions", .white)])
                CodeLine(number: 15, segments: [])
                CodeLine(number: 16, segments: [("    var", .pink), (" body", .cyan), (": some View {", .white)])
                CodeLine(number: 17, segments: [("        ZStack", .cyan), ("(alignment: .leading) {", .white)])
                CodeLine(number: 18, segments: [("            sidebarContent", .green), ("()", .white)])
                Spacer()
            }
            .padding(14)
        }
    }
}

private struct CodeLine: View {
    let number: Int
    let segments: [(String, Color)]

    var body: some View {
        HStack(spacing: 0) {
            Text(String(format: "%2d  ", number))
                .foregroundStyle(Color.white.opacity(0.22))
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Text(segment.0).foregroundStyle(segment.1.opacity(0.78))
            }
        }
        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
        .lineLimit(1)
    }
}

private struct MarketingBrowserContent: View {
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        Text("developer.apple.com/documentation")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                    .frame(height: 24)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(10)

            Divider().overlay(Color.white.opacity(0.07))

            VStack(alignment: .leading, spacing: 12) {
                Text("SwiftUI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text("View")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text("A type that represents part of your app's user interface.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.055))
                    .frame(height: 72)
                    .overlay(alignment: .leading) {
                        Text("@MainActor\nprotocol View")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.94, green: 0.40, blue: 0.66))
                            .padding(14)
                    }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MarketingTerminalWindow: View {
    var body: some View {
        VStack(spacing: 0) {
            MarketingPlainTitleBar(title: "Terminal — winmux")
            VStack(alignment: .leading, spacing: 8) {
                Text("$ swift run winmux-marketing-renderer")
                    .foregroundStyle(Color.white.opacity(0.74))
                Text("Rendering production SwiftUI views…")
                    .foregroundStyle(Color(red: 0.44, green: 0.84, blue: 0.65))
                Text("resources/marketing/winmux-card-collage-swiftui.png")
                    .foregroundStyle(Color.white.opacity(0.38))
                Spacer()
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.040, green: 0.043, blue: 0.060))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
    }
}

private struct MarketingNotesWindow: View {
    var body: some View {
        VStack(spacing: 0) {
            MarketingPlainTitleBar(title: "Launch notes")
            VStack(alignment: .leading, spacing: 11) {
                Text("A calmer desktop")
                    .font(.system(size: 17, weight: .bold))
                Label("Projects keep work together", systemImage: "checkmark.circle.fill")
                Label("Tabs reduce workspace sprawl", systemImage: "checkmark.circle.fill")
                Label("The sidebar keeps context visible", systemImage: "checkmark.circle.fill")
                Spacer()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.70))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.060, green: 0.055, blue: 0.082))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
    }
}

private struct MarketingPlainTitleBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.22)).frame(width: 8, height: 8)
            Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.35)).frame(width: 8, height: 8)
            Spacer()
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.46))
            Spacer()
            Color.clear.frame(width: 36)
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Color.white.opacity(0.035))
    }
}

private struct MarketingFeatureCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.72, green: 0.66, blue: 1))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.90))
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
        }
    }
}

@MainActor
private enum MarketingFixtures {
    private final class TabGroupIdentity {}

    private static let codeIdentity = TabGroupIdentity()
    private static let browserIdentity = TabGroupIdentity()
    private static let defaultProject = WorkspaceProjectId(rawValue: "default")

    static let sidebarSnapshot = WorkspaceSidebarSnapshot(
        workspaces: [
            WorkspaceSidebarWorkspaceViewModel(
                name: "code",
                projectId: defaultProject,
                displayName: "Code",
                sidebarLabel: "C",
                isGeneratedName: false,
                monitorScopeId: "display-main",
                monitorName: "Studio Display",
                isFocused: true,
                isVisible: true,
                items: [
                    .init(kind: .tabGroup(.init(
                        representativeWindowId: 101,
                        workspaceName: "code",
                        title: "WinMux development",
                        windowCount: 3,
                        isFocused: true,
                        tabs: [
                            sidebarWindow(101, workspace: "code", app: "Xcode", bundle: "com.apple.dt.Xcode", title: "SidebarView.swift", focused: true),
                            sidebarWindow(102, workspace: "code", app: "Safari", bundle: "com.apple.Safari", title: "SwiftUI docs"),
                            sidebarWindow(103, workspace: "code", app: "Terminal", bundle: "com.apple.Terminal", title: "Build and test"),
                        ]
                    ))),
                ]
            ),
            WorkspaceSidebarWorkspaceViewModel(
                name: "research",
                projectId: defaultProject,
                displayName: "Browser",
                sidebarLabel: "B",
                isGeneratedName: false,
                monitorScopeId: "display-main",
                monitorName: "Studio Display",
                isFocused: false,
                isVisible: false,
                items: [
                    .init(kind: .window(sidebarWindow(201, workspace: "research", app: "Safari", bundle: "com.apple.Safari", title: "Apple Developer"))),
                    .init(kind: .window(sidebarWindow(202, workspace: "research", app: "Notes", bundle: "com.apple.Notes", title: "Launch notes"))),
                ]
            ),
        ],
        projects: [
            WorkspaceSidebarProjectViewModel(id: defaultProject, displayName: "WinMux", colorHex: "#7C6CF2"),
            WorkspaceSidebarProjectViewModel(id: "personal", displayName: "Personal", colorHex: "#58A6FF"),
        ],
        activeProjectId: defaultProject,
        monitorScopes: [
            WorkspaceSidebarMonitorScopeViewModel(
                id: "default",
                displayName: "All Displays",
                subtitle: nil,
                systemImageName: "display.2",
                isFocusedMonitor: true
            ),
        ],
        selectedMonitorScopeId: "default",
        targetMonitorScopeId: "display-main",
        focusedMonitorScopeId: "display-main",
        visibleWidth: 280,
        hoveredWorkspaceName: nil,
        dropPreview: nil,
        configuration: WorkspaceSidebarConfiguration(
            collapsedWidth: 44,
            expandedWidth: 280,
            topPadding: 12,
            showMonitorSelector: true,
            showsClock: true,
            showsSeconds: false,
            showsDate: true,
            showsWeekday: true,
            showsStatusPills: true,
            chromeStyle: .liquidGlass,
            solidChromeColor: .midnight,
            solidChromeCustomColor: "#191B20"
        )
    )

    static let codeTabStrip = tabStrip(
        identity: codeIdentity,
        workspace: "code",
        activeWindowId: 101,
        tabs: [
            tab(101, workspace: "code", app: "Xcode", bundle: "com.apple.dt.Xcode", title: "WorkspaceSidebarView.swift", active: true),
            tab(102, workspace: "code", app: "Terminal", bundle: "com.apple.Terminal", title: "winmux — swift run"),
        ]
    )

    static let browserTabStrip = tabStrip(
        identity: browserIdentity,
        workspace: "code",
        activeWindowId: 103,
        tabs: [
            tab(103, workspace: "code", app: "Safari", bundle: "com.apple.Safari", title: "SwiftUI documentation", active: true),
            tab(104, workspace: "code", app: "Safari", bundle: "com.apple.Safari", title: "Window management"),
        ]
    )

    private static func sidebarWindow(
        _ id: UInt32,
        workspace: String,
        app: String,
        bundle: String,
        title: String,
        focused: Bool = false
    ) -> WorkspaceSidebarWindowViewModel {
        WorkspaceSidebarWindowViewModel(
            windowId: id,
            workspaceName: workspace,
            appName: app,
            appBundleId: bundle,
            appBundlePath: nil,
            title: title,
            isFocused: focused
        )
    }

    private static func tab(
        _ id: UInt32,
        workspace: String,
        app: String,
        bundle: String,
        title: String,
        active: Bool = false
    ) -> WindowTabItemViewModel {
        WindowTabItemViewModel(
            windowId: id,
            workspaceName: workspace,
            appName: app,
            appBundleId: bundle,
            appBundlePath: nil,
            title: title,
            isActive: active
        )
    }

    private static func tabStrip(
        identity: TabGroupIdentity,
        workspace: String,
        activeWindowId: UInt32,
        tabs: [WindowTabItemViewModel]
    ) -> WindowTabStripViewModel {
        WindowTabStripViewModel(
            id: ObjectIdentifier(identity),
            workspaceName: workspace,
            frame: CGRect(x: 0, y: 0, width: 400, height: 40),
            groupFrame: CGRect(x: 0, y: 0, width: 400, height: 400),
            activeWindowId: activeWindowId,
            activeWindowCornerRadius: 16,
            tabs: tabs,
            occludingFloatingWindowFrames: []
        )
    }
}
