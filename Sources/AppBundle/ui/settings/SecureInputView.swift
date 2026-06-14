import AppKit
import Carbon
import SwiftUI

private let iconSize = CGSize(width: 50, height: 50)
private let textSize = CGSize(width: 440, height: 110)

public final class SecureInputPanel: NSPanelHud {
    @MainActor public static var shared: SecureInputPanel = SecureInputPanel()
    private var hostingView = NSHostingView(rootView: SecureInputView())

    override private init() {
        super.init()
    }

    @MainActor
    public func refresh() {
        if let activeMode, TrayMenuModel.shared.isEnabled &&
            config.modes[activeMode]?.bindings.isEmpty == false && IsSecureEventInputEnabled()
        {
            if isVisible { return }
            self.contentView?.subviews.removeAll()
            hostingView = NSHostingView(rootView: SecureInputView())
            hostingView.frame = NSRect(x: 0, y: 0, width: iconSize.width, height: iconSize.height)
            self.contentView?.addSubview(hostingView)
            let x = mainMonitor.width - iconSize.width - 20
            let panelFrame = NSRect(x: x, y: 20, width: iconSize.width, height: iconSize.width)
            self.setFrame(panelFrame, display: true)
            self.orderFrontRegardless()
        } else {
            close()
        }
    }

    public func updateFrame(isMinimized: Bool) {
        let width = isMinimized ? iconSize.width : textSize.width
        let height = isMinimized ? iconSize.height : textSize.height
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let x = mainMonitor.width - width - 20
        let panelFrame = NSRect(x: x, y: 20, width: width, height: height)
        self.setFrame(panelFrame, display: true)
    }
}

struct SecureInputView: View {
    @State var isMinimized: Bool = true

    var body: some View {
        ZStack(alignment: .center) {
            GlassSurface(shape: RoundedRectangle(cornerRadius: RadiusToken.section, style: .continuous))
            if isMinimized {
                Image(systemName: "lock.shield.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                Text("WinMux cannot respond to keyboard shortcuts while **Secure Input** is active. **Secure Input** is a macOS security feature that prevents applications from reading keyboard events.")
                    .font(.title3)
                    .padding(10)
            }
        }
        .foregroundStyle(Color.white.opacity(GlassToken.textPrimary))
        .clipShape(RoundedRectangle(cornerRadius: RadiusToken.section, style: .continuous))
        .onTapGesture {
            if !isMinimized {
                SecureInputPanel.shared.refresh()
            }
            isMinimized.toggle()
            SecureInputPanel.shared.updateFrame(isMinimized: isMinimized)
        }
        .frame(
            width: isMinimized ? iconSize.width : textSize.width,
            height: isMinimized ? iconSize.height : textSize.height,
        )
    }
}
