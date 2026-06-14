@MainActor
func activeWindowContentFrame(
    _ activeWindow: Window,
    container: TilingContainer,
) -> Rect? {
    currentWindowDragActualRect(activeWindow) ??
        activeWindow.lastAppliedLayoutPhysicalRect ??
        container.lastAppliedLayoutPhysicalRect
}
