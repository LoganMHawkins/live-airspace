import XCTest
@testable import LiveAirspaceKit

final class OutlierTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func report(_ source: SourceID, lat: Double = 45.0, lon: Double = -75.0, age: TimeInterval = 1) -> SourceReport {
        SourceReport(icao24: "abc123", source: source, latitude: lat, longitude: lon, altitudeFt: 30_000,
                     groundSpeedKt: 450, trackDeg: 90, positionTime: now.addingTimeInterval(-age))
    }

    func testSingleDissenterAmongThreeIsSetAside() {
        let out = AirspaceMerger().merge([
            report(.adsbLol), report(.adsbFi, lon: -75.001), report(.openSky, lat: 45.2),
        ], now: now)[0]
        XCTAssertEqual(out.outlierSource, .openSky)
        guard case .confirmed = out.agreement else { return XCTFail("expected the other two to confirm each other, got \(out.agreement)") }
        XCTAssertEqual(out.confirmingSources, 2)
        XCTAssertEqual(out.latitude, 45.0, accuracy: 0.01)  // the outlier's position was not used
    }

    func testThreeWayDisagreementStaysDisputed() {
        let out = AirspaceMerger().merge([
            report(.adsbLol), report(.adsbFi, lat: 45.2), report(.openSky, lat: 44.8),
        ], now: now)[0]
        XCTAssertNil(out.outlierSource)
        XCTAssertTrue(out.agreement.isDisputed)
    }

    func testTwoWayDisputeTrustsTheMoreReliableSource() {
        let reports = [report(.adsbLol, lat: 45.0, age: 1), report(.adsbFi, lat: 45.2, age: 3)]
        let trustFi = AirspaceMerger().merge(reports, now: now, reliability: [.adsbFi: 0.99, .adsbLol: 0.6])[0]
        XCTAssertEqual(trustFi.latitude, 45.2, accuracy: 0.001)
        let trustLol = AirspaceMerger().merge(reports, now: now, reliability: [.adsbFi: 0.6, .adsbLol: 0.99])[0]
        XCTAssertEqual(trustLol.latitude, 45.0, accuracy: 0.001)
    }

    func testWatchRules() {
        let ac = Aircraft(id: "a", callsign: "ACA123", typeCode: "A388", latitude: 0, longitude: 0, positionTime: now, sources: [.adsbLol], agreement: .single)
        XCTAssertTrue(WatchRule(kind: .airline, value: "aca").matches(ac))
        XCTAssertFalse(WatchRule(kind: .airline, value: "WJA").matches(ac))
        XCTAssertTrue(WatchRule(kind: .type, value: "A388").matches(ac))
        XCTAssertFalse(WatchRule(kind: .registration, value: "C-GITS").matches(ac))
        // A registration used as a callsign must not match an airline code.
        var ga = ac; ga.callsign = "CGITS"
        XCTAssertFalse(WatchRule(kind: .airline, value: "CGI").matches(ga))
    }
}
