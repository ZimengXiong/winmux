import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    @ViewBuilder
    var interactiveSectionContent: some View {
        if isCompact {
            Button(action: handleSectionClick) {
                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(sectionShape)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(sectionShape)
        } else {
            sectionContent.contentShape(sectionShape)
        }
    }

    var sectionActivationButton: some View {
        Button(action: handleSectionClick) {
            Color.clear.contentShape(sectionShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(workspace.displayName)
    }

    var sectionContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            headerSlot
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            windowRows
            dropPreviewRow
        }
    }

    @ViewBuilder
    var headerSlot: some View {
        header
            .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
    }
}
