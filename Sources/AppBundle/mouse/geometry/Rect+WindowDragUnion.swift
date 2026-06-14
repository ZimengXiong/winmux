import Common

extension Rect {
    static func union(_ rects: some Sequence<Rect>) -> Rect? {
        var iterator = rects.makeIterator()
        guard let first = iterator.next() else { return nil }
        var minX = first.minX
        var minY = first.minY
        var maxX = first.maxX
        var maxY = first.maxY
        while let rect = iterator.next() {
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        return Rect(topLeftX: minX, topLeftY: minY, width: maxX - minX, height: maxY - minY)
    }
}
