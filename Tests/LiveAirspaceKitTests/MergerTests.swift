import XCTest
@testable import LiveAirspaceKit

final class MergerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func report(_ source: SourceID, hex: String = "abc123", lat: Double = 45.0, lon: Double = -75.0,
                alt: Double? = 30_000, gs: Double? = 450, track: Double? = 90, age: TimeInterval = 2,
                callsign: String? = nil, type: String? = nil) -> SourceReport {
        SourceReport(icao24: hex, source: source, callsign: callsign, typeCode: type, latitude: lat, longitude: lon,
                     altitudeFt: alt, groundSpeedKt: gs, trackDeg: track, positionTime: now.addingTimeInterval(-age))
    }

    func testSingleSourceIsMarkedSingle() {
        let out = AirspaceMerger().merge([report(.adsbLol)], now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].agreement, .single)
        XCTAssertEqual(out[0].sources, [.adsbLol])
    }

    func testAgreeingSourcesAreConfirmed() {
        let out = AirspaceMerger().merge([
            report(.adsbLol, callsign: "ACA123", type: "A320"),
            report(.openSky, lat: 45.002, lon: -75.001),
        ], now: now)
        XCTAssertEqual(out.count, 1)
        guard case .confirmed(let spread) = out[0].agreement else { return XCTFail("expected confirmed") }
        XCTAssertLessThan(spread, 1)
        XCTAssertEqual(out[0].sources, [.adsbLol, .openSky])
        XCTAssertEqual(out[0].callsign, "ACA123")
        XCTAssertEqual(out[0].typeCode, "A320")
    }

    func testDifferentFixAgesAreReconciledByDeadReckoning() {
        // OpenSky's fix is 30 s old; 450 kt east for 30 s is ~3.75 nm, so the raw positions differ a lot
        // but the extrapolated ones should agree.
        let lead = report(.adsbLol, lon: -75.0, age: 1)
        let oldPos = Geo.project(Coordinate(latitude: 45, longitude: -75), trackDeg: 90, distanceNM: -450 * 29 / 3600)
        let stale = report(.openSky, lat: oldPos.latitude, lon: oldPos.longitude, age: 30)
        let out = AirspaceMerger().merge([lead, stale], now: now)
        guard case .confirmed = out[0].agreement else { return XCTFail("expected confirmed, got \(out[0].agreement)") }
    }

    func testFarApartSourcesAreDisputed() {
        let out = AirspaceMerger().merge([report(.adsbLol), report(.adsbFi, lat: 45.2)], now: now)
        XCTAssertTrue(out[0].agreement.isDisputed)
    }

    func testAltitudeDisagreementIsFlagged() {
        let out = AirspaceMerger().merge([report(.adsbLol, alt: 30_000), report(.adsbFi, alt: 31_200)], now: now)
        XCTAssertTrue(out[0].altitudeDisputed)
        let ok = AirspaceMerger().merge([report(.adsbLol, alt: 30_000), report(.adsbFi, alt: 30_100)], now: now)
        XCTAssertFalse(ok[0].altitudeDisputed)
    }

    func testStaleAndImplausibleReportsAreDropped() {
        let out = AirspaceMerger().merge([
            report(.adsbLol, hex: "stale1", age: 120),
            report(.adsbLol, hex: "fast01", gs: 4_000),
            report(.adsbLol, hex: "null01", lat: 0, lon: 0),
            report(.adsbLol, hex: "high01", alt: 200_000),
            report(.adsbLol, hex: "good01"),
        ], now: now)
        XCTAssertEqual(out.map(\.id), ["good01"])
    }

    func testHexMatchingIsCaseInsensitive() {
        let out = AirspaceMerger().merge([report(.adsbLol, hex: "ABC123"), report(.adsbFi, hex: "abc123")], now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].sources.count, 2)
    }

    func testPositionExtrapolationMovesAlongTrack() {
        let ac = AirspaceMerger().merge([report(.adsbLol, age: 0)], now: now)[0]
        let later = ac.position(at: now.addingTimeInterval(60))
        XCTAssertEqual(later.latitude, 45.0, accuracy: 0.01)
        XCTAssertGreaterThan(later.longitude, -75.0)  // heading east
        XCTAssertEqual(Geo.distanceNM(Coordinate(latitude: 45, longitude: -75), later), 7.5, accuracy: 0.1)
    }
}
