import XCTest
@testable import LiveAirspaceKit

final class ParsingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReadsbParsing() throws {
        let json = """
        {"now": 1, "ac": [
          {"hex":"8004df","flight":"AIC190  ","r":"VT-ALQ","t":"B77W","alt_baro":29000,"gs":520.8,"track":65.26,"baro_rate":-64,"squawk":"6307","lat":44.77,"lon":-76.19,"seen_pos":0.5},
          {"hex":"c0ffee","alt_baro":"ground","lat":45.3,"lon":-75.6,"seen_pos":3},
          {"hex":"~123456","lat":45.0,"lon":-75.0},
          {"hex":"nopos1","alt_baro":1000}
        ]}
        """.data(using: .utf8)!
        let r = try ReadsbSource.parse(json, source: .adsbLol, now: now)
        XCTAssertEqual(r.count, 2)  // non-ICAO and position-less rows dropped
        XCTAssertEqual(r[0].callsign, "AIC190")
        XCTAssertEqual(r[0].typeCode, "B77W")
        XCTAssertEqual(r[0].altitudeFt, 29_000)
        XCTAssertEqual(r[0].positionTime, now.addingTimeInterval(-0.5))
        XCTAssertTrue(r[1].onGround)
        XCTAssertEqual(r[1].positionTime, now.addingTimeInterval(-3))
    }

    func testOpenSkyParsingConvertsUnits() throws {
        let json = """
        {"time":1,"states":[["3c4a15","DLH433  ","Germany",1799999998,1799999998,-75.0067,45.0593,11277.6,false,272.28,68.96,-0.33,null,11475.72,"6551",false,0]]}
        """.data(using: .utf8)!
        let r = try OpenSkySource.parse(json, now: now)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].callsign, "DLH433")
        XCTAssertEqual(r[0].altitudeFt!, 37_000, accuracy: 5)       // 11277.6 m
        XCTAssertEqual(r[0].groundSpeedKt!, 529.3, accuracy: 0.5)   // 272.28 m/s
        XCTAssertEqual(r[0].positionTime, now.addingTimeInterval(-2))
    }

    func testOpenSkyEmptyAirspaceIsNotAnError() throws {
        let r = try OpenSkySource.parse(#"{"time":1,"states":null}"#.data(using: .utf8)!, now: now)
        XCTAssertTrue(r.isEmpty)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try ReadsbSource.parse(Data("[]".utf8), source: .adsbFi, now: now))
    }
}

final class CredentialStoreTests: XCTestCase {
    func testKeychainRoundTrip() throws {
        let service = "com.bureau.liveairspace.tests.\(UUID().uuidString)"
        defer { OpenSkyCredentialStore.remove(service: service) }
        let creds = OpenSkyCredentials(clientID: "someone-api-client", clientSecret: "not-a-real-secret")
        guard OpenSkyCredentialStore.save(creds, service: service) else { throw XCTSkip("keychain unavailable in this environment") }
        XCTAssertEqual(OpenSkyCredentialStore.load(service: service), creds)
        OpenSkyCredentialStore.remove(service: service)
        XCTAssertNil(OpenSkyCredentialStore.load(service: service))
    }
}
