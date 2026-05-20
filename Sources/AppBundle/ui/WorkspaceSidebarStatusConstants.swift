import Foundation
import SwiftUI

let workspaceSidebarStatusCornerRadius: CGFloat = 8
let workspaceSidebarStatusRefreshInterval: Duration = .seconds(5)
let workspaceSidebarExpandedStatusLeadingPadding: CGFloat = 7
let workspaceSidebarExpandedStatusTrailingPadding: CGFloat = 12
let workspaceSidebarExpandedStatusDateMinimumWidth: CGFloat = 190
let workspaceSidebarExpandedStatusPillsMinimumWidth: CGFloat = 150

func workspaceSidebarExpandedStatusShowsDate(sectionWidth: CGFloat, configured: Bool) -> Bool {
    configured && sectionWidth >= workspaceSidebarExpandedStatusDateMinimumWidth
}

func workspaceSidebarExpandedStatusShowsPills(sectionWidth: CGFloat, configured: Bool) -> Bool {
    configured && sectionWidth >= workspaceSidebarExpandedStatusPillsMinimumWidth
}
