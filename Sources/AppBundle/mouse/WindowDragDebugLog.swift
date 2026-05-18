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
