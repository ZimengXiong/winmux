import SwiftUI

struct WindowIntentPreviewOverlayView: View {
    let model: WindowTabDropPreviewViewModel

    @ViewBuilder
    var body: some View {
        if let dropIntentOverlay = model.dropIntentOverlay {
            WindowDropIntentOverlayView(model: dropIntentOverlay)
                .frame(width: model.containerFrame.width, height: model.containerFrame.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
