@testable import AppBundle
import XCTest

final class WindowDropIntentResolverTest: XCTestCase {
    func testResolvesTopBandAsTabZone() {
        let resolution = resolve(point: CGPoint(x: 150, y: 115))
        XCTAssertEqual(resolution?.intent.zone, .tab)
        XCTAssertEqual(resolution?.intent.sourceWindowId, 1)
        XCTAssertEqual(resolution?.intent.targetWindowId, 2)
    }

    func testResolvesBodyZones() {
        XCTAssertEqual(resolve(point: CGPoint(x: 110, y: 210))?.intent.zone, .left)
        XCTAssertEqual(resolve(point: CGPoint(x: 290, y: 210))?.intent.zone, .right)
        XCTAssertEqual(resolve(point: CGPoint(x: 200, y: 160))?.intent.zone, .top)
        XCTAssertEqual(resolve(point: CGPoint(x: 200, y: 210))?.intent.zone, .middle)
        XCTAssertEqual(resolve(point: CGPoint(x: 200, y: 285))?.intent.zone, .bottom)
    }

    func testRejectsSourceAsTargetAndOutsidePointer() {
        let frame = Rect(topLeftX: 100, topLeftY: 100, width: 210, height: 210)
        XCTAssertNil(WindowDropIntentResolver().resolve(
            sourceWindowId: 1,
            targetWindowId: 1,
            pointer: CGPoint(x: 150, y: 150),
            targetFrame: frame,
        ))
        XCTAssertNil(WindowDropIntentResolver().resolve(
            sourceWindowId: 1,
            targetWindowId: 2,
            pointer: CGPoint(x: 99, y: 150),
            targetFrame: frame,
        ))
    }

    private func resolve(point: CGPoint) -> WindowDropIntentResolution? {
        WindowDropIntentResolver().resolve(
            sourceWindowId: 1,
            targetWindowId: 2,
            pointer: point,
            targetFrame: Rect(topLeftX: 100, topLeftY: 100, width: 210, height: 210),
        )
    }
}
