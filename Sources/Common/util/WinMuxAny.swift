import Foundation
import AppKit

public protocol WinMuxAny {}

extension WinMuxAny {
    @discardableResult
    @inlinable
    public func apply(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }

    @discardableResult
    @inlinable
    public func also(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }

    @inlinable public func takeIf(_ predicate: (Self) -> Bool) -> Self? { predicate(self) ? self : nil }
    @inlinable public func then<R>(_ body: (Self) -> R) -> R { body(self) }
}

extension Int: WinMuxAny {}
extension String: WinMuxAny {}
extension Character: WinMuxAny {}
extension Regex: WinMuxAny {}
extension Array: WinMuxAny {}
extension URL: WinMuxAny {}
extension CGFloat: WinMuxAny {}
extension AXUIElement: WinMuxAny {}
extension CGPoint: WinMuxAny {}
