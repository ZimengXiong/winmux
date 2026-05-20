@testable import AppBundle
import XCTest

final class WorkspaceSidebarSystemStatusTest: XCTestCase {
    func testBatteryLabelsAndAccessibilityDescriptions() {
        XCTAssertEqual(
            WorkspaceSidebarBatterySnapshot(chargePercent: 82, state: .charging).label,
            "82%"
        )
        XCTAssertEqual(
            WorkspaceSidebarBatterySnapshot(chargePercent: 82, state: .charging).accessibilityDescription,
            "Battery 82 percent, charging"
        )

        XCTAssertEqual(
            WorkspaceSidebarBatterySnapshot(chargePercent: 82, state: .ac).label,
            "AC 82%"
        )
        XCTAssertEqual(
            WorkspaceSidebarBatterySnapshot(chargePercent: 82, state: .ac).accessibilityDescription,
            "Battery 82 percent, on AC power"
        )

        XCTAssertEqual(
            WorkspaceSidebarBatterySnapshot(chargePercent: 37, state: .discharging).label,
            "37%"
        )
        XCTAssertEqual(
            WorkspaceSidebarBatterySnapshot(chargePercent: 37, state: .discharging).accessibilityDescription,
            "Battery 37 percent, discharging"
        )
    }

    func testAudioLabels() {
        XCTAssertEqual(
            WorkspaceSidebarAudioSnapshot(volumePercent: 64, isMuted: false).label,
            "64%"
        )
        XCTAssertEqual(
            WorkspaceSidebarAudioSnapshot(volumePercent: 64, isMuted: false).symbolName,
            "speaker.wave.2.fill"
        )

        XCTAssertEqual(
            WorkspaceSidebarAudioSnapshot(volumePercent: 64, isMuted: true).label,
            "Mute"
        )
        XCTAssertEqual(
            WorkspaceSidebarAudioSnapshot(volumePercent: 64, isMuted: true).accessibilityDescription,
            "Sound muted"
        )
    }

    func testNetworkLabelUsesUppercaseInterfaceName() {
        XCTAssertEqual(
            WorkspaceSidebarNetworkSnapshot(interfaceName: "en7").label,
            "EN7"
        )
        XCTAssertEqual(
            WorkspaceSidebarNetworkSnapshot(interfaceName: nil).label,
            "Offline"
        )
    }
}
