import AppKit
import Common
import SwiftUI

let workspaceSidebarPanelId = "WinMux.workspaceSidebar"
let workspaceSidebarContentLeadingInset: CGFloat = 12
let workspaceSidebarContentTrailingInset: CGFloat = 12
let workspaceSidebarCompactRailHorizontalInset: CGFloat = 7
let workspaceSidebarSectionInnerHorizontalInset: CGFloat = 5
let workspaceSidebarSectionGap: CGFloat = 5
let workspaceSidebarBadgeWidth: CGFloat = 22
let workspaceSidebarHeaderSpacing: CGFloat = 10
let workspaceSidebarHeaderRowLeadingPadding: CGFloat = 6
let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
let workspaceSidebarPlateCornerRadius: CGFloat = 12
let workspaceSidebarSectionCornerRadius: CGFloat = workspaceSidebarPlateCornerRadius
let workspaceSidebarRowCornerRadius: CGFloat = 8
let workspaceSidebarRowHorizontalPadding: CGFloat = 4
let workspaceSidebarWindowRowsLeadingIndent: CGFloat = 8
let workspaceSidebarAppIconSize: CGFloat = 14
let workspaceSidebarAppIconTextSpacing: CGFloat = 6
let workspaceSidebarTabGroupChildLeadingIndent: CGFloat = workspaceSidebarAppIconSize + workspaceSidebarAppIconTextSpacing - 2
let workspaceSidebarControlHeight: CGFloat = 30
let workspaceSidebarDropdownHeight: CGFloat = 28
let workspaceSidebarDropdownCornerRadius: CGFloat = 9
let workspaceSidebarDropdownPadding: CGFloat = 7
let workspaceSidebarDropdownLabelSize: CGFloat = 11.5
let workspaceSidebarDropdownSymbolSize: CGFloat = 10.5
let workspaceSidebarPagerHeight: CGFloat = 32
let workspaceSidebarActiveWorkspaceTint = Color(nsColor: .systemBlue)
let workspaceSidebarWorkspaceSectionHeaderHeight: CGFloat = 32
let workspaceSidebarWorkspaceRowHeight: CGFloat = 24
let workspaceSidebarWorkspaceSectionHeightCompact: CGFloat = 32
let workspaceSidebarWorkspaceSectionHeightExpanded: CGFloat = 32
let workspaceSidebarProjectDotFrameHeight: CGFloat = 32
let workspaceSidebarMenuRowHeight: CGFloat = 28
let workspaceSidebarMenuRowSpacing: CGFloat = 3
let workspaceSidebarMenuRowHorizontalPadding: CGFloat = 10
let workspaceSidebarHoverAnimation: Animation = .interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.06)
let workspaceSidebarReducedMotionHoverAnimation: Animation = .easeOut(duration: 0.14)
let workspaceSidebarProjectSwipeIntentThreshold: CGFloat = 5
let workspaceSidebarProjectSwipeNavigateThreshold: CGFloat = 44
let workspaceSidebarProjectSwipeCreateThreshold: CGFloat = 104
let workspaceSidebarProjectSwipeFormationStart: CGFloat = 22
let workspaceSidebarHoverOpenThresholdFraction: CGFloat = 0.75
let workspaceSidebarDisplayEdgeCompactionMargin: CGFloat = 12
@MainActor
var workspaceSidebarDropTargets: [WorkspaceSidebarDropTarget] = []

struct WorkspaceSidebarProjectColorPreset: Hashable, Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}

let workspaceSidebarProjectColorPresets: [WorkspaceSidebarProjectColorPreset] = [
    WorkspaceSidebarProjectColorPreset(name: "Blue", hex: "#60A5FA"),
    WorkspaceSidebarProjectColorPreset(name: "Cyan", hex: "#22D3EE"),
    WorkspaceSidebarProjectColorPreset(name: "Green", hex: "#34D399"),
    WorkspaceSidebarProjectColorPreset(name: "Yellow", hex: "#FBBF24"),
    WorkspaceSidebarProjectColorPreset(name: "Orange", hex: "#FB923C"),
    WorkspaceSidebarProjectColorPreset(name: "Red", hex: "#F87171"),
    WorkspaceSidebarProjectColorPreset(name: "Pink", hex: "#F472B6"),
    WorkspaceSidebarProjectColorPreset(name: "Violet", hex: "#A78BFA"),
]
