import Foundation

extension String {
    mutating func deleteLastWord() {
        self = deletingLastWord()
    }

    func deletingLastWord() -> String {
        var result = self
        while let last = result.last, last.isWhitespace {
            result.removeLast()
        }
        while let last = result.last, !last.isWhitespace {
            result.removeLast()
        }
        return result
    }
}
