import CoreGraphics

@MainActor
func logWindowDragHitTestIfNeeded(signature: String, _ message: @autoclosure () -> String) {
    guard lastWindowDragHitTestLogSignature != signature else { return }
    lastWindowDragHitTestLogSignature = signature
    debugFocusLog(message())
}

@MainActor
func logWindowDragIntentIfNeeded(signature: String, _ message: @autoclosure () -> String) {
    guard lastWindowDragIntentLogSignature != signature else { return }
    lastWindowDragIntentLogSignature = signature
    debugFocusLog(message())
}

@MainActor
func logWindowDragLive(_ message: @autoclosure () -> String) {
    debugFocusLog("[drag-live] \(message())")
}

func debugDescribeDragPointBucket(_ point: CGPoint) -> String {
    let bucketSize = CGFloat(80)
    let x = Int((point.x / bucketSize).rounded(.down))
    let y = Int((point.y / bucketSize).rounded(.down))
    return "\(x),\(y)"
}
