import SwiftUI

@ViewBuilder
func exposeCardThumb(_ item: ExposeWindowItem, w: CGFloat, h: CGFloat, hov: Bool) -> some View {
    Group {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.1))
                .overlay(
                    Image(systemName: "macwindow")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.1))
                )
        }
    }
    .frame(width: w, height: h)
    .shadow(color: .black.opacity(hov ? 0.35 : 0.15), radius: hov ? 12 : 6, y: hov ? 6 : 2)
}
