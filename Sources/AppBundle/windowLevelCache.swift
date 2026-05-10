import CoreGraphics
import Foundation

@MainActor
private var cache: [UInt32: MacOsWindowLevel] = [:]

@MainActor
func getWindowLevel(for windowId: UInt32) -> MacOsWindowLevel? {
    if let existing = cache[windowId] { return existing }

    var result: [UInt32: MacOsWindowLevel] = [:]
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let windowInfos = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else { return nil }
    for dict in windowInfos {

        guard let rawWindowLayer = dict[kCGWindowLayer as String] as? NSNumber else { continue }
        let windowLayer = rawWindowLayer.intValue

        guard let rawWindowId = dict[kCGWindowNumber as String] as? NSNumber else { continue }
        let windowId = rawWindowId.uint32Value

        result[windowId] = .new(windowLevel: windowLayer)
    }
    cache = result
    return result[windowId]
}

enum MacOsWindowLevel: Sendable, Equatable {
    case normalWindow
    case alwaysOnTopWindow
    case unknown(windowLevel: Int)

    static func new(windowLevel: Int) -> MacOsWindowLevel {
        switch windowLevel {
            case 0: .normalWindow
            case 3: .alwaysOnTopWindow
            default: .unknown(windowLevel: windowLevel)
        }
    }

    static func fromJson(_ json: Json) -> MacOsWindowLevel? {
        switch json {
            case .string(let str) where str == "normalWindow": .normalWindow
            case .string(let str) where str == "alwaysOnTopWindow": .alwaysOnTopWindow
            case .int(let int): .new(windowLevel: int)
            default: nil
        }
    }

    func toJson() -> Json {
        switch self {
            case .normalWindow: .string("normalWindow")
            case .alwaysOnTopWindow: .string("alwaysOnTopWindow")
            case .unknown(let layerNumber): .int(layerNumber)
        }
    }
}
