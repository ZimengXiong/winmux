import AppKit
import Common
import SwiftUI

let exposeOverviewCoordinateSpace = "WinMux.expose.overview"
let exposeCardTitleHeight: CGFloat = 20
let exposeExpandedGroupSpacing: CGFloat = 16
let exposeExpandedGroupHoverPadding: CGFloat = 26

struct ExposeHoverTargetFrame: Equatable {
    let itemId: UInt32
    let frame: CGRect
}

struct ExposeHoverTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [ExposeHoverTargetFrame] = []

    static func reduce(value: inout [ExposeHoverTargetFrame], nextValue: () -> [ExposeHoverTargetFrame]) {
        value.append(contentsOf: nextValue())
    }
}

func hoveredExposeItemId(at location: CGPoint, within frames: [ExposeHoverTargetFrame]) -> UInt32? {
    frames.last(where: { $0.frame.contains(location) })?.itemId
}

struct ExposeExpandedGroupFrame: Equatable {
    let groupId: String
    let frame: CGRect
}

struct ExposeCollapsedGroupFrame: Equatable {
    let groupId: String
    let frame: CGRect
}

struct ExposeExpandedGroupFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ExposeExpandedGroupFrame] = []

    static func reduce(value: inout [ExposeExpandedGroupFrame], nextValue: () -> [ExposeExpandedGroupFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct ExposeCollapsedGroupFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ExposeCollapsedGroupFrame] = []

    static func reduce(value: inout [ExposeCollapsedGroupFrame], nextValue: () -> [ExposeCollapsedGroupFrame]) {
        value.append(contentsOf: nextValue())
    }
}

func exposeExpandedGroupHoverRect(
    groupId: String,
    within frames: [ExposeExpandedGroupFrame],
    padding: CGFloat,
) -> CGRect? {
    let groupFrames = frames
        .filter { $0.groupId == groupId }
        .map(\.frame)
    guard let first = groupFrames.first else { return nil }
    let union = groupFrames.dropFirst().reduce(first) { $0.union($1) }
    return union.insetBy(dx: -padding, dy: -padding)
}

func shouldKeepExpandedGroupVisible(
    location: CGPoint,
    groupId: String,
    expandedFrames: [ExposeExpandedGroupFrame],
    collapsedOriginFrame: CGRect?,
    padding: CGFloat,
) -> Bool {
    if let collapsedOriginFrame,
       collapsedOriginFrame.insetBy(dx: -padding, dy: -padding).contains(location) {
        return true
    }
    if let expandedRect = exposeExpandedGroupHoverRect(
        groupId: groupId,
        within: expandedFrames,
        padding: padding,
    ) {
        return expandedRect.contains(location)
    }
    return false
}

func hoveredCollapsedGroupFrame(
    at location: CGPoint,
    within frames: [ExposeCollapsedGroupFrame],
    padding: CGFloat = 0,
) -> ExposeCollapsedGroupFrame? {
    frames.last(where: { $0.frame.insetBy(dx: -padding, dy: -padding).contains(location) })
}

func orderedExposeItemsForExpandedGroup(_ items: [ExposeWindowItem]) -> [ExposeWindowItem] {
    guard let focusedIndex = items.firstIndex(where: \.isFocused) else { return items }
    var ordered = items
    let focusedItem = ordered.remove(at: focusedIndex)
    ordered.insert(focusedItem, at: 0)
    return ordered
}

func exposeThumbnailWindowIds(from entries: [ExposeEntry]) -> [UInt32] {
    var seen: Set<UInt32> = []
    var result: [UInt32] = []
    func append(_ id: UInt32) {
        if seen.insert(id).inserted {
            result.append(id)
        }
    }
    for entry in entries {
        switch entry {
            case .window(let window):
                append(window.id)
            case .group(let group):
                for item in group.items {
                    append(item.id)
                }
        }
    }
    return result
}

