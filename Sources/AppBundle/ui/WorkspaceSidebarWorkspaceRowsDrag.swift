import Foundation
import SwiftUI

extension View {
    @ViewBuilder
    func workspaceSidebarDrag(enabled: Bool, provider: @escaping () -> NSItemProvider) -> some View {
        if enabled {
            onDrag(provider)
        } else {
            self
        }
    }
}
