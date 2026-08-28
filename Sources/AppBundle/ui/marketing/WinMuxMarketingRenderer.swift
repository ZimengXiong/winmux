import AppKit
import SwiftUI

/// Exports a deterministic marketing composition that embeds WinMux's production SwiftUI views.
/// The renderer does not capture the screen or read pixels from application windows.
@MainActor
public func renderWinMuxMarketingImage(to outputURL: URL) throws {
    try renderMarketingView(WinMuxMarketingCanvas(), to: outputURL)
}

/// Exports a focused proof containing one real Safari surface and two WinMux tabs.
@MainActor
public func renderWinMuxSafariProofImage(to outputURL: URL) throws {
    try renderMarketingView(WinMuxSafariProofCanvas(), to: outputURL)
}

/// Exports a collage of native Helium, Ghostty, and Finder window surfaces.
@MainActor
public func renderWinMuxAppsProofImage(to outputURL: URL) throws {
    try renderMarketingView(WinMuxAppsProofCanvas(), to: outputURL)
}

/// Exports a tiled Safari and Plasticity workspace using their measured split ratio.
@MainActor
public func renderWinMuxSafariPlasticityProofImage(to outputURL: URL) throws {
    try renderMarketingView(WinMuxSafariPlasticityProofCanvas(), to: outputURL)
}

@MainActor
private func renderMarketingView<Content: View>(_ rootView: Content, to outputURL: URL) throws {
    let size = CGSize(width: 1_600, height: 900)
    let content = rootView
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

private struct WinMuxSafariProofCanvas: View {
    private let strip = MarketingFixtures.browserTabStrip

    private var groupSize: CGSize {
        let maximumContentSize = CGSize(width: 1_360, height: 780)
        guard let pixels = MarketingAsset.pixelSize(named: "safari-retina.png"),
              pixels.width > 0,
              pixels.height > 0
        else {
            return CGSize(width: 1_262, height: 820)
        }

        let aspectRatio = pixels.width / pixels.height
        let contentWidth = min(maximumContentSize.width, maximumContentSize.height * aspectRatio)
        let contentHeight = contentWidth / aspectRatio
        return CGSize(width: contentWidth, height: contentHeight + strip.frame.height)
    }

    var body: some View {
        ZStack {
            MarketingDesktopWallpaper(
                imageName: "macos-blue-wallpaper.jpg",
                darkeningOpacity: 0.58
            )

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )

            MarketingCapturedTabWindow(
                strip: strip,
                imageName: "safari-retina.png",
                contentMode: .fit
            )
            .frame(width: groupSize.width, height: groupSize.height)
        }
        .frame(width: 1_600, height: 900)
        .clipped()
    }
}

private struct WinMuxAppsProofCanvas: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            MarketingDesktopWallpaper(
                imageName: "macos-blue-wallpaper.jpg",
                darkeningOpacity: 0.48
            )

            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.30)],
                startPoint: .top,
                endPoint: .bottom
            )

            MarketingCapturedTabWindow(
                strip: MarketingFixtures.appsTabStrip,
                imageName: "helium-retina.png",
                imageAlignment: .top
            )
            .frame(width: 918, height: 852)
            .offset(x: 64, y: 24)

            MarketingCapturedTabWindow(
                strip: MarketingFixtures.browserTabStrip,
                imageName: "safari-retina.png",
                imageAlignment: .top
            )
            .frame(width: 582, height: 852)
            .offset(x: 994, y: 24)

            if let sidebar = MarketingAsset.image(named: "winmux-retina.png") {
                Image(nsImage: sidebar)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 900, alignment: .topLeading)
                    .frame(width: 560, height: 900, alignment: .topLeading)
                    .offset(x: 0, y: 0)
                    .zIndex(5)
            }
        }
        .frame(width: 1_600, height: 900)
        .clipped()
    }
}

private struct WinMuxSafariPlasticityProofCanvas: View {
    private let safariWidth: CGFloat = 587.3637
    private let plasticityWidth: CGFloat = 938.6363
    private let tileHeight: CGFloat = 864

    var body: some View {
        ZStack(alignment: .topLeading) {
            MarketingDesktopWallpaper(
                imageName: "macos-blue-wallpaper.jpg",
                darkeningOpacity: 0.46
            )

            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.26)],
                startPoint: .top,
                endPoint: .bottom
            )

            MarketingCapturedTabWindow(
                strip: MarketingFixtures.safariCurrentTabStrip,
                imageName: "safari-current-retina.png",
                imageAlignment: .top,
                shadowOpacity: 0
            )
            .frame(width: safariWidth, height: tileHeight)
            .offset(x: 58, y: 28)

            MarketingCapturedTabWindow(
                strip: MarketingFixtures.plasticityTabStrip,
                imageName: "plasticity-current-retina.png",
                imageAlignment: .top,
                shadowOpacity: 0
            )
            .frame(width: plasticityWidth, height: tileHeight)
            .offset(x: 653.3637, y: 28)

        }
        .frame(width: 1_600, height: 900)
        .overlay(alignment: .topLeading) {
            if let sidebar = MarketingAsset.image(named: "winmux-retina.png") {
                MarketingTranslucentCapturedSidebar(image: sidebar)
            }
        }
        .clipped()
    }
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

            WorkspaceSidebarView(snapshot: sidebarSnapshot)
                .frame(width: sidebarSnapshot.visibleWidth, height: 906)
                .zIndex(5)

            MarketingCapturedTabWindow(strip: codeTabs, imageName: "xcode-winmux.png")
                .frame(width: 590, height: 620)
                .offset(x: 300, y: 44)
                .rotationEffect(.degrees(-0.6))
                .zIndex(2)

            MarketingCapturedTabWindow(strip: browserTabs, imageName: "safari-swiftui.png")
                .frame(width: 735, height: 500)
                .offset(x: 820, y: 76)
                .rotationEffect(.degrees(0.45))
                .zIndex(3)

            MarketingCapturedWindow(imageName: "finder-winmux.png")
                .frame(width: 390, height: 260)
                .offset(x: 390, y: 584)
                .rotationEffect(.degrees(-1.1))
                .zIndex(3.2)

            campaignCopy
                .frame(width: 700, alignment: .leading)
                .offset(x: 835, y: 627)
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
    private static func url(named name: String) -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return root.appendingPathComponent("resources/marketing/captures/\(name)")
    }

    static func image(named name: String) -> NSImage? {
        NSImage(contentsOf: url(named: name))
    }

    static func pixelSize(named name: String) -> CGSize? {
        guard let data = try? Data(contentsOf: url(named: name)),
              let representation = NSBitmapImageRep(data: data)
        else { return nil }
        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}

private struct MarketingDesktopWallpaper: View {
    var imageName = "macos-sonoma-wallpaper.png"
    var darkeningOpacity = 0.0

    var body: some View {
        ZStack {
            if let wallpaper = MarketingAsset.image(named: imageName) {
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(red: 0.12, green: 0.18, blue: 0.42)
            }

            Color(red: 0.005, green: 0.018, blue: 0.075)
                .opacity(darkeningOpacity)

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
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color(red: 0.015, green: 0.055, blue: 0.13).opacity(0.50))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
        }
    }
}

/// Wraps a real application-window capture with WinMux's production tab-group chrome.
private struct MarketingCapturedTabWindow: View {
    let strip: WindowTabStripViewModel
    let imageName: String
    var contentMode: ContentMode = .fill
    var imageAlignment: Alignment = .center
    var shadowOpacity = 0.50

    var body: some View {
        GeometryReader { proxy in
            let innerRect = WindowTabGroupShellShape.innerRect(
                in: CGRect(origin: .zero, size: proxy.size),
                tabBarHeight: strip.frame.height
            )
            let outerShape = WindowTabGroupOuterShape(
                activeWindowCornerRadius: strip.activeWindowCornerRadius
            )

            ZStack(alignment: .top) {
                outerShape
                    .fill(Color(red: 0.025, green: 0.10, blue: 0.22).opacity(0.20))
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.blue.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }

                if let image = MarketingAsset.image(named: imageName) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(
                            width: innerRect.width,
                            height: innerRect.height,
                            alignment: imageAlignment
                        )
                        .clipped()
                        .clipShape(RoundedRectangle(
                            cornerRadius: strip.activeWindowCornerRadius,
                            style: .continuous
                        ))
                        .offset(y: innerRect.minY)

                }

                MarketingMeasuredTabGroupFrameView(strip: strip, groupSize: proxy.size)
                WindowTabStripView(strip: strip)
                    .frame(height: strip.frame.height)
            }
            .clipShape(outerShape)
            .shadow(color: .black.opacity(shadowOpacity), radius: 28, y: 17)
        }
    }
}

private struct MarketingMeasuredTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize

    var body: some View {
        let tabHeight = min(strip.frame.height, groupSize.height)
        let outerShape = WindowTabGroupOuterShape(
            activeWindowCornerRadius: strip.activeWindowCornerRadius
        )
        let innerShape = MarketingMeasuredWindowBoundaryShape(
            tabBarHeight: tabHeight,
            cornerRadius: strip.activeWindowCornerRadius
        )
        let shellShape = MarketingMeasuredWindowShellShape(
            tabBarHeight: tabHeight,
            cornerRadius: strip.activeWindowCornerRadius
        )

        ZStack(alignment: .topLeading) {
            GlassSurface(
                shape: outerShape,
                style: config.workspaceSidebar.chromeStyle,
                solidColor: config.workspaceSidebar.resolvedSolidChromeColor
            )
            .mask {
                shellShape.fill(style: FillStyle(eoFill: true))
            }

            outerShape
                .stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: windowTabGroupFrameStrokeWidth)
                .glassShadow(.raised)

            Rectangle()
                .fill(Color.white.opacity(GlassToken.separatorOpacity))
                .frame(height: StrokeToken.hairline)
                .offset(y: tabHeight - StrokeToken.hairline)

            innerShape
                .stroke(mattePanelInsetShadow, lineWidth: windowTabGroupFrameInnerStrokeWidth)
        }
        .frame(width: groupSize.width, height: groupSize.height)
        .allowsHitTesting(false)
    }
}

private struct MarketingMeasuredWindowShellShape: Shape {
    let tabBarHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addPath(WindowTabGroupOuterShape(activeWindowCornerRadius: cornerRadius).path(in: rect))
        path.addPath(MarketingMeasuredWindowBoundaryShape(
            tabBarHeight: tabBarHeight,
            cornerRadius: cornerRadius
        ).path(in: rect))
        return path
    }
}

private struct MarketingMeasuredWindowBoundaryShape: Shape {
    let tabBarHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let innerRect = WindowTabGroupShellShape.innerRect(
            in: rect,
            tabBarHeight: tabBarHeight
        )
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: innerRect)
    }
}

private struct MarketingTranslucentCapturedSidebar: View {
    let image: NSImage

    var body: some View {
        let sidebarShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 20,
            topTrailingRadius: 20,
            style: .continuous
        )

        ZStack(alignment: .topLeading) {
            sidebarShape
            .fill(Color(red: 0.012, green: 0.045, blue: 0.115).opacity(0.68))
            .overlay {
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.blue.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 934, alignment: .topLeading)
                .frame(width: 560, height: 934, alignment: .topLeading)
                .blendMode(.screen)
                .opacity(0.76)
        }
        .frame(width: 50, height: 934, alignment: .topLeading)
        .clipShape(sidebarShape)
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
    private static let heliumIdentity = TabGroupIdentity()
    private static let safariCurrentIdentity = TabGroupIdentity()
    private static let plasticityIdentity = TabGroupIdentity()
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
            tab(103, workspace: "code", app: "Safari", bundle: "com.apple.Safari", title: "macOS 27 — Apple", active: true),
            tab(104, workspace: "code", app: "Safari", bundle: "com.apple.Safari", title: "Apple Intelligence"),
        ]
    )

    static let appsTabStrip = tabStrip(
        identity: heliumIdentity,
        workspace: "work",
        activeWindowId: 301,
        tabs: [
            tab(301, workspace: "work", app: "Helium", bundle: "net.imput.helium", title: "alpaca engineering", active: true),
            tab(302, workspace: "work", app: "Ghostty", bundle: "com.mitchellh.ghostty", title: "WinMux"),
            tab(303, workspace: "work", app: "Finder", bundle: "com.apple.finder", title: "winmux"),
        ]
    )

    static let safariCurrentTabStrip = tabStrip(
        identity: safariCurrentIdentity,
        workspace: "design",
        activeWindowId: 601,
        tabs: [
            tab(
                601,
                workspace: "design",
                app: "Safari",
                bundle: "com.apple.Safari",
                path: "/Applications/Safari.app",
                title: "alpaca engineering",
                active: true
            ),
            tab(
                602,
                workspace: "design",
                app: "Google Chrome",
                bundle: "com.google.Chrome",
                path: "/Applications/Google Chrome.app",
                title: "Chrome"
            ),
        ],
        cornerRadius: 14
    )

    static let plasticityTabStrip = tabStrip(
        identity: plasticityIdentity,
        workspace: "design",
        activeWindowId: 701,
        tabs: [
            tab(
                701,
                workspace: "design",
                app: "Plasticity",
                bundle: "com.electron.plasticity",
                path: "/Applications/Plasticity.app",
                title: "5X.plasticity",
                active: true
            ),
            tab(
                702,
                workspace: "design",
                app: "Autodesk Fusion",
                bundle: "com.autodesk.dls.streamer.scriptapp.Autodesk-Fusion",
                path: "/Users/xzm/Applications/Autodesk Fusion.app",
                title: "Fusion"
            ),
            tab(
                703,
                workspace: "design",
                app: "Finder",
                bundle: "com.apple.finder",
                path: "/System/Library/CoreServices/Finder.app",
                title: "Finder"
            ),
        ],
        cornerRadius: 14
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
        path: String? = nil,
        title: String,
        active: Bool = false
    ) -> WindowTabItemViewModel {
        WindowTabItemViewModel(
            windowId: id,
            workspaceName: workspace,
            appName: app,
            appBundleId: bundle,
            appBundlePath: path,
            title: title,
            isActive: active
        )
    }

    private static func tabStrip(
        identity: TabGroupIdentity,
        workspace: String,
        activeWindowId: UInt32,
        tabs: [WindowTabItemViewModel],
        cornerRadius: CGFloat = 16
    ) -> WindowTabStripViewModel {
        WindowTabStripViewModel(
            id: ObjectIdentifier(identity),
            workspaceName: workspace,
            frame: CGRect(x: 0, y: 0, width: 400, height: 40),
            groupFrame: CGRect(x: 0, y: 0, width: 400, height: 400),
            activeWindowId: activeWindowId,
            activeWindowCornerRadius: cornerRadius,
            tabs: tabs,
            occludingFloatingWindowFrames: []
        )
    }
}
