import AppKit
import Common
import MASShortcut
import SwiftUI

struct ManagedDirectionalShortcutsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var availableWidth: CGFloat = .zero

    private static let horizontalLayoutMinWidth: CGFloat = 880

    var body: some View {
        Group {
            if availableWidth >= Self.horizontalLayoutMinWidth {
                HStack(alignment: .top, spacing: 24) {
                    directionalPad(title: "Focus", prefix: "focus") {
                        FocusDemoView()
                    }

                    directionalPad(title: "Move", prefix: "move") {
                        MoveDemoView()
                    }

                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    directionalPad(title: "Focus", prefix: "focus") {
                        FocusDemoView()
                    }

                    directionalPad(title: "Move", prefix: "move") {
                        MoveDemoView()
                    }
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ManagedDirectionalShortcutsWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(ManagedDirectionalShortcutsWidthKey.self) { width in
            availableWidth = width
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func directionalPad<Demo: View>(
        title: String,
        prefix: String,
        @ViewBuilder demo: () -> Demo
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            CompassPad(model: model, title: title, prefix: prefix, demo: demo)
        }
    }
}

private struct ManagedDirectionalShortcutsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DemoColors {
    static let win1 = Color.blue
    static let win2 = Color.orange
    static let win3 = Color.purple
}

struct DemoContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .frame(width: 100, height: 60)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5))
    }
}

struct FocusDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win1).opacity(phase == 1 ? 1 : 0.3)
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win2).opacity(phase == 2 ? 1 : 0.3)
            }
            .animation(.easeInOut(duration: 0.2), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 4 // 0: reset, 1: left focused, 2: right focused, 3: delay
        }
    }
}

struct MoveDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            GeometryReader { geo in
                let spacing: CGFloat = 4
                let winW = (geo.size.width - spacing) / 2
                let h = geo.size.height
                
                // Left position x: winW / 2
                // Right position x: winW + spacing + winW / 2
                
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win1)
                    .frame(width: winW, height: h)
                    .position(
                        x: phase == 1 ? (winW + spacing + winW / 2) : winW / 2,
                        y: h / 2
                    )
                
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win2)
                    .frame(width: winW, height: h)
                    .position(
                        x: phase == 1 ? winW / 2 : (winW + spacing + winW / 2),
                        y: h / 2
                    )
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3 // 0: A-B, 1: B-A, 2: delay
        }
    }
}

struct SplitDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let spacing: CGFloat = 4
                
                // Left Window (Win 1)
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win1).opacity(0.4)
                    .frame(width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3, height: h)
                    .position(x: phase == 1 ? (w - spacing) / 4 : (w - 2 * spacing) / 6, y: h / 2)
                
                // Container for Win 2 and Win 3
                Group {
                    // Win 2 (Top in split)
                    RoundedRectangle(cornerRadius: 4).fill(DemoColors.win2).opacity(0.4)
                        .frame(
                            width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3,
                            height: phase == 1 ? (h - spacing) / 2 : h
                        )
                        .position(
                            x: phase == 1 ? 3 * (w - spacing) / 4 + spacing : (w - 2 * spacing) / 2 + spacing,
                            y: phase == 1 ? (h - spacing) / 4 : h / 2
                        )
                    
                    // Win 3 (Bottom in split, Focused)
                    RoundedRectangle(cornerRadius: 4).fill(DemoColors.win3)
                        .frame(
                            width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3,
                            height: phase == 1 ? (h - spacing) / 2 : h
                        )
                        .position(
                            x: phase == 1 ? 3 * (w - spacing) / 4 + spacing : 5 * (w - 2 * spacing) / 6 + 2 * spacing,
                            y: phase == 1 ? 3 * (h - spacing) / 4 + spacing : h / 2
                        )
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3 // 0: side-by-side, 1: stacked, 2: delay
        }
    }
}

struct CompassPad<Demo: View>: View {
    @ObservedObject var model: ShortcutSettingsModel
    let title: String
    let prefix: String
    let demo: Demo

    init(model: ShortcutSettingsModel, title: String, prefix: String, @ViewBuilder demo: () -> Demo) {
        self.model = model
        self.title = title
        self.prefix = prefix
        self.demo = demo()
    }

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                recorderCell(for: "\(prefix)-up", label: "Up")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                recorderCell(for: "\(prefix)-left", label: "Left")
                demo
                    .frame(width: 120, height: 80)
                recorderCell(for: "\(prefix)-right", label: "Right")
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                recorderCell(for: "\(prefix)-down", label: "Down")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func recorderCell(for id: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ShortcutRecorderView(
                shortcut: .init(get: { model.shortcutValue(for: id) },
                                set: { model.setShortcutValue($0, for: id) }),
                onChange: { _ in }
            )
            .frame(width: 120, height: 22)
        }
    }
}

struct SnapGridPad: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                recorderCell(for: "snap-top-left", label: "Top Left")
                recorderCell(for: "snap-top-half", label: "Top")
                recorderCell(for: "snap-top-right", label: "Top Right")
            }
            GridRow {
                recorderCell(for: "snap-left-half", label: "Left")
                recorderCell(for: "snap-maximize", label: "Full")
                recorderCell(for: "snap-right-half", label: "Right")
            }
            GridRow {
                recorderCell(for: "snap-bottom-left", label: "Bottom Left")
                recorderCell(for: "snap-bottom-half", label: "Bottom")
                recorderCell(for: "snap-bottom-right", label: "Bottom Right")
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func recorderCell(for id: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ShortcutRecorderView(
                shortcut: .init(get: { model.shortcutValue(for: id) },
                                set: { model.setShortcutValue($0, for: id) }),
                onChange: { _ in }
            )
            .frame(width: 120, height: 22)
        }
    }
}

