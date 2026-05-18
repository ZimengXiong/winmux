import AppKit

func captureExposeThumbnail(_ windowId: UInt32) -> NSImage? {
    guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(windowId),
                                           [.boundsIgnoreFraming, .nominalResolution]) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
