import XCTest
@testable import DuoStatusProPlugin

@MainActor
final class DuoStatusProSystemIconControllerTests: XCTestCase {
    /// Records visibility writes and restarts instead of touching real
    /// ControlCenter preferences.
    private final class FakeBackend: DuoStatusProSystemIconBackend {
        var visibility: [DuoStatusProSystemIcon: Bool]
        var writes: [(icon: DuoStatusProSystemIcon, visible: Bool)] = []
        var restartCount = 0

        init(visibility: [DuoStatusProSystemIcon: Bool] = [:]) {
            self.visibility = visibility
        }

        func isVisible(_ icon: DuoStatusProSystemIcon) -> Bool {
            visibility[icon] ?? true
        }

        func setVisible(_ icon: DuoStatusProSystemIcon, _ visible: Bool) {
            visibility[icon] = visible
            writes.append((icon, visible))
        }

        func restartControlCenter() {
            restartCount += 1
        }
    }

    func testHidingOneIconLeavesTheOtherUntouched() {
        let backend = FakeBackend()
        let controller = DuoStatusProSystemIconController(backend: backend)

        controller.apply(hideBattery: true, hideWiFi: false)

        XCTAssertEqual(backend.visibility[.battery], false)
        XCTAssertEqual(backend.writes.count, 1)
        XCTAssertEqual(backend.writes.first?.icon, .battery)
        XCTAssertNil(backend.visibility[.wifi])
    }

    func testReapplyingTheSameStateDoesNotRestartControlCenter() {
        let backend = FakeBackend()
        let controller = DuoStatusProSystemIconController(backend: backend)

        controller.apply(hideBattery: true, hideWiFi: true)
        let writesAfterFirstApply = backend.writes.count
        controller.apply(hideBattery: true, hideWiFi: true)

        XCTAssertEqual(backend.writes.count, writesAfterFirstApply)
    }

    func testRestoreReturnsIconsToTheStateRecordedBeforeTheFirstChange() {
        // Wi-Fi was already hidden by the user before the plugin touched anything.
        let backend = FakeBackend(visibility: [.battery: true, .wifi: false])
        let controller = DuoStatusProSystemIconController(backend: backend)

        controller.apply(hideBattery: true, hideWiFi: true)
        controller.restore()

        XCTAssertEqual(backend.visibility[.battery], true)
        XCTAssertEqual(backend.visibility[.wifi], false, "A pre-hidden icon stays hidden on restore")
    }

    func testRestoreWithoutAnyPriorChangeIsANoOp() {
        let backend = FakeBackend()
        let controller = DuoStatusProSystemIconController(backend: backend)

        controller.restore()

        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertEqual(backend.restartCount, 0)
    }

    func testUnhidingAfterHidingRestoresVisibilityWithoutRestore() {
        let backend = FakeBackend()
        let controller = DuoStatusProSystemIconController(backend: backend)

        controller.apply(hideBattery: true, hideWiFi: true)
        controller.apply(hideBattery: false, hideWiFi: false)

        XCTAssertEqual(backend.visibility[.battery], true)
        XCTAssertEqual(backend.visibility[.wifi], true)
    }
}
