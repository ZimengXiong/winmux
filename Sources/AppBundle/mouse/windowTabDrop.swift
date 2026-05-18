import AppKit
import Common

let windowDropPreviewInset: CGFloat = 0
let windowTabInsertPreviewExtraHeight: CGFloat = 18
let windowTabInsertPreviewMinHeight: CGFloat = 52
let windowTabInsertInteractionHorizontalInset: CGFloat = 24
let windowTabInsertInteractionTopInset: CGFloat = 12
let windowTabInsertInteractionBottomInset: CGFloat = 32
let windowTabInsertStickyTrackingHorizontalInset: CGFloat = 24
let windowTabInsertStickyTrackingTopInset: CGFloat = 20
let windowTabInsertStickyTrackingBottomInset: CGFloat = 36

@MainActor
var pendingWindowDragIntent: PendingWindowDragIntent? = nil
@MainActor
var windowDragActualRectRefreshTask: Task<Void, Never>? = nil
@MainActor
var windowDragActualRectCache: [UInt32: Rect] = [:]
@MainActor
var lastWindowDragHitTestLogSignature: String? = nil
@MainActor
var lastWindowDragIntentLogSignature: String? = nil
