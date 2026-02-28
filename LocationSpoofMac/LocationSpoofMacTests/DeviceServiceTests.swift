import XCTest
@testable import LocationSpoofMac

final class DeviceServiceTests: XCTestCase {
    func testFindReturnsExecutablePath() {
        let service = DeviceService(pymobiledevicePath: "/usr/bin/true")
        XCTAssertTrue(service.isAvailable)
    }

    func testIsAvailableReturnsFalseForBadPath() {
        let service = DeviceService(pymobiledevicePath: "/nonexistent/path")
        XCTAssertFalse(service.isAvailable)
    }

    func testRunProcessSucceeds() throws {
        let output = try DeviceService.runProcess("/bin/echo", arguments: ["hello"])
        XCTAssertEqual(output, "hello")
    }

    func testRunProcessFailsOnBadCommand() {
        XCTAssertThrowsError(try DeviceService.runProcess("/bin/false"))
    }
}
