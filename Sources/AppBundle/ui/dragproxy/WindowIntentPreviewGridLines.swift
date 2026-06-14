import SwiftUI

struct WindowIntentPreviewGridLines: Shape {
    func path(in rect: CGRect) -> Path {
        let tabHeight = min(max(rect.height * 0.18, 32), rect.height / 3)
        let dropMinY = rect.minY + tabHeight
        let dropHeight = max(rect.height - tabHeight, 0)
        let columnWidth = rect.width / 3
        let rowHeight = dropHeight / 3
        let firstColumnEdge = rect.minX + columnWidth
        let secondColumnEdge = rect.maxX - columnWidth
        let firstRowEdge = dropMinY + rowHeight
        let secondRowEdge = rect.maxY - rowHeight

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: dropMinY))
        path.addLine(to: CGPoint(x: rect.maxX, y: dropMinY))
        path.move(to: CGPoint(x: firstColumnEdge, y: dropMinY))
        path.addLine(to: CGPoint(x: firstColumnEdge, y: rect.maxY))
        path.move(to: CGPoint(x: secondColumnEdge, y: dropMinY))
        path.addLine(to: CGPoint(x: secondColumnEdge, y: rect.maxY))
        path.move(to: CGPoint(x: firstColumnEdge, y: firstRowEdge))
        path.addLine(to: CGPoint(x: secondColumnEdge, y: firstRowEdge))
        path.move(to: CGPoint(x: firstColumnEdge, y: secondRowEdge))
        path.addLine(to: CGPoint(x: secondColumnEdge, y: secondRowEdge))
        return path
    }
}
