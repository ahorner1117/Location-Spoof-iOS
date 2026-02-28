import XCTest
@testable import LocationSpoof

final class SpoofMessageTests: XCTestCase {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func testSetMessageEncodesCorrectly() throws {
        let msg = SpoofMessage.set(lat: 35.6762, lng: 139.6503)
        let data = try encoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "set")
        XCTAssertEqual(json["lat"] as? Double, 35.6762)
        XCTAssertEqual(json["lng"] as? Double, 139.6503)
    }

    func testClearMessageEncodesCorrectly() throws {
        let msg = SpoofMessage.clear
        let data = try encoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "clear")
        XCTAssertNil(json["lat"])
        XCTAssertNil(json["lng"])
    }

    func testPingMessageEncodesCorrectly() throws {
        let msg = SpoofMessage.ping
        let data = try encoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "ping")
    }

    func testMessageRoundTrips() throws {
        let original = SpoofMessage.set(lat: -33.8688, lng: 151.2093)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SpoofMessage.self, from: data)

        XCTAssertEqual(decoded.action, .set)
        XCTAssertEqual(decoded.lat, -33.8688)
        XCTAssertEqual(decoded.lng, 151.2093)
    }

    func testResponseOkEncodesCorrectly() throws {
        let resp = SpoofResponse.ok(spoofing: true, lat: 40.7128, lng: -74.0060)
        let data = try encoder.encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["spoofing"] as? Bool, true)
        XCTAssertEqual(json["lat"] as? Double, 40.7128)
    }

    func testResponseErrorEncodesCorrectly() throws {
        let resp = SpoofResponse.error("Device not connected")
        let data = try encoder.encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["message"] as? String, "Device not connected")
    }

    func testResponsePongEncodesCorrectly() throws {
        let resp = SpoofResponse.pong(device: "Anthony's iPhone", spoofing: false)
        let data = try encoder.encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["status"] as? String, "pong")
        XCTAssertEqual(json["device"] as? String, "Anthony's iPhone")
        XCTAssertEqual(json["spoofing"] as? Bool, false)
    }
}
