import AppKit
import Foundation

extension KeyedDecodingContainer where K == AgentOperation.CodingKeys {
    func decodeAgentPaneRef(primaryKey: K, paneIdKey: K, windowIdKey: K) throws -> AgentPaneRef {
        if contains(primaryKey) {
            return try decode(AgentPaneRef.self, forKey: primaryKey)
        }
        if let paneId = try decodeIfPresent(String.self, forKey: paneIdKey) {
            return AgentPaneRef(paneId: paneId, windowId: nil, tabGroupId: nil)
        }
        if let windowId = try decodeIfPresent(UInt32.self, forKey: windowIdKey) {
            return AgentPaneRef(paneId: nil, windowId: windowId, tabGroupId: nil)
        }
        return try decode(AgentPaneRef.self, forKey: primaryKey)
    }

    func decodeWindowIdArray(primaryKey: K, aliasKey: K) throws -> [UInt32] {
        if contains(primaryKey) {
            return try decode([UInt32].self, forKey: primaryKey)
        }
        return try decode([UInt32].self, forKey: aliasKey)
    }

    func decodeAgentSizeAxis(axisKey: K, directionKey: K) throws -> AgentLayoutDirection? {
        if let axis = try decodeIfPresent(AgentLayoutDirection.self, forKey: axisKey) {
            return axis
        }
        return try decodeIfPresent(AgentLayoutDirection.self, forKey: directionKey)
    }
}

extension KeyedDecodingContainer {
    func decodeAgentSizeRatio(sizeKey: K, percentKey: K) throws -> CGFloat {
        if let percent = try decodeIfPresent(CGFloat.self, forKey: percentKey) {
            return try normalizeAgentSizeRatio(percent, percentKey: percentKey)
        }
        return try normalizeAgentSizeRatio(try decode(CGFloat.self, forKey: sizeKey), percentKey: sizeKey)
    }

    func decodeAgentSizeRatioIfPresent(sizeKey: K, percentKey: K) throws -> CGFloat? {
        if let percent = try decodeIfPresent(CGFloat.self, forKey: percentKey) {
            return try normalizeAgentSizeRatio(percent, percentKey: percentKey)
        }
        guard let size = try decodeIfPresent(CGFloat.self, forKey: sizeKey) else { return nil }
        return try normalizeAgentSizeRatio(size, percentKey: sizeKey)
    }
}

func normalizedAgentOperationType(_ type: String) -> String {
    type.filter { $0 != "_" && $0 != "-" }.lowercased()
}

func normalizeAgentSizeRatio<K: CodingKey>(_ raw: CGFloat, percentKey key: K) throws -> CGFloat {
    guard raw.isFinite, raw > 0 else {
        throw DecodingError.dataCorrupted(.init(codingPath: [key], debugDescription: "size must be greater than 0"))
    }
    let ratio = raw > 1 ? raw / 100 : raw
    guard ratio > 0, ratio <= 1 else {
        throw DecodingError.dataCorrupted(.init(codingPath: [key], debugDescription: "size must be a ratio from 0 to 1, or a percent from 1 to 100"))
    }
    return ratio
}
