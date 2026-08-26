import AppKit
import SwiftUI

struct WorkspaceSidebarDropPreviewView: View {
    let preview: WorkspaceSidebarDropPreviewViewModel
    let rowHeight: CGFloat

    private var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
    }

    var body: some View {
        if preview.targetsNewWorkspace {
            newWorkspacePreview
        } else {
            previewRows
                .padding(.leading, workspaceSidebarWindowRowsLeadingIndent)
                .allowsHitTesting(false)
        }
    }

    private var newWorkspacePreview: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: workspaceSidebarHeaderSpacing) {
                Text("New Workspace")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text("\(preview.windowCount)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(.leading, workspaceSidebarHeaderRowLeadingPadding)
            .padding(.trailing, workspaceSidebarRowHorizontalPadding)
            .frame(height: rowHeight + 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            previewRows
                .padding(.leading, workspaceSidebarWindowRowsLeadingIndent)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
        .background(sectionShape.fill(Color.white.opacity(0.015)))
        .overlay {
            sectionShape.strokeBorder(
                Color.white.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, dash: [5, 3])
            )
        }
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var previewRows: some View {
        if preview.isTabGroup {
            VStack(alignment: .leading, spacing: 1) {
                tabGroupHeaderRow
                ForEach(Array(preview.tabItems.enumerated()), id: \.offset) { _, tab in
                    singleWindowRow(
                        title: tab.title,
                        appBundleIdentifier: tab.appBundleIdentifier,
                        appBundlePath: tab.appBundlePath
                    )
                    .padding(.leading, 14)
                }
            }
        } else {
            singleWindowRow(
                title: preview.label,
                appBundleIdentifier: preview.appBundleIdentifier,
                appBundlePath: preview.appBundlePath
            )
        }
    }

    private var tabGroupHeaderRow: some View {
        let icons = preview.tabItems.map { ($0.appBundleIdentifier, $0.appBundlePath) }
        return HStack(spacing: 6) {
            if !icons.isEmpty {
                HStack(spacing: -3) {
                    ForEach(Array(icons.prefix(4).enumerated()), id: \.offset) { _, icon in
                        if let image = appIconImage(bundleIdentifier: icon.0, bundlePath: icon.1) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .cornerRadius(3)
                        }
                    }
                }
            }
            Text(preview.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text("\(preview.windowCount)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.50))
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowShape.fill(Color.white.opacity(0.085)))
    }

    private func singleWindowRow(
        title: String,
        appBundleIdentifier: String?,
        appBundlePath: String?
    ) -> some View {
        HStack(spacing: 6) {
            if let icon = appIconImage(bundleIdentifier: appBundleIdentifier, bundlePath: appBundlePath) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .cornerRadius(3)
            }
            Text(title)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, 1)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowShape.fill(Color.white.opacity(0.06)))
    }
}
