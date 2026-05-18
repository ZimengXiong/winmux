import AppKit
import Common
import SwiftUI

let workspaceSidebarPanelId = "WinMux.workspaceSidebar"
let workspaceSidebarContentLeadingInset: CGFloat = 8
let workspaceSidebarContentTrailingInset: CGFloat = 8
let workspaceSidebarCompactRailHorizontalInset: CGFloat = 4
let workspaceSidebarSectionInnerHorizontalInset: CGFloat = 4
let workspaceSidebarBadgeWidth: CGFloat = 18
let workspaceSidebarHeaderSpacing: CGFloat = 10
let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
let workspaceSidebarSectionCornerRadius: CGFloat = 10
let workspaceSidebarRowCornerRadius: CGFloat = 6
let workspaceSidebarRowHorizontalPadding: CGFloat = 7
let workspaceSidebarHeaderLeadingPadding: CGFloat = 3
let workspaceSidebarWindowRowsLeadingIndent: CGFloat = 4
let workspaceSidebarPagerHeight: CGFloat = 32
let workspaceSidebarActiveWorkspaceTint = Color(nsColor: .systemBlue)
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
