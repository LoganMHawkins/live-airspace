import XCTest
@testable import LiveAirspaceKit

struct FakeSource: AirspaceSource {
    let id: SourceID
    let minimumInterval: TimeInterval = 0.05
    let result: @Sendable (Date) throws -> [SourceReport]
    func fetch(center: Coordinate, radiusNM: Double, now: Date) async throws -> [SourceReport] { try result(now) }
}

func report(_ id: SourceID, hex: String = "abc123", lat: Double = 45.1, lon: Double = -75.6, now: Date) -> SourceReport {
    SourceReport(icao24: hex, source: id, callsign: "ACA\(hex.suffix(3))", latitude: lat, longitude: lon, altitudeFt: 30_000,
                 groundSpeedKt: 450, trackDeg: 90, positionTime: now)
}

@MainActor
final class StoreTests: XCTestCase {
    func eventually(_ timeout: TimeInterval = 4, _ condition: @escaping () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    func testMergesAcrossSourcesAndTracksHealth() async {
        let store = AirspaceStore(config: .default, sources: [
            FakeSource(id: .adsbLol) { now in [report(.adsbLol, now: now)] },
            FakeSource(id: .adsbFi) { now in [report(.adsbFi, now: now)] },
            FakeSource(id: .openSky) { _ in throw SourceError.badStatus(503) },
        ], enrichment: nil)
        store.start()
        defer { store.stop() }

        let ok = await eventually { store.aircraft.first?.sources.count == 2 && store.status[.openSky]?.lastError != nil }
        XCTAssertTrue(ok)
        XCTAssertEqual(store.aircraft.count, 1)
        XCTAssertEqual(store.status[.openSky]?.lastError, "HTTP 503")
        let degraded = await eventually { if case .degraded(let down) = store.feedHealth { return down == [.openSky] } else { return false } }
        XCTAssertTrue(degraded, "one failing feed should read as degraded, got \(store.feedHealth)")
    }

    func testAllFeedsDownIsReported() async {
        let store = AirspaceStore(config: .default, sources: [
            FakeSource(id: .adsbLol) { _ in throw SourceError.badStatus(500) },
            FakeSource(id: .adsbFi) { _ in throw SourceError.rateLimited(retryAfter: 1) },
        ], enrichment: nil)
        store.start()
        defer { store.stop() }
        let down = await eventually { store.feedHealth == .down }
        XCTAssertTrue(down)
    }

    func testSelectionCyclesByDistanceAndWraps() async {
        let store = AirspaceStore(config: AirspaceConfig(name: "t", center: Coordinate(latitude: 45, longitude: -75)), sources: [
            FakeSource(id: .adsbLol) { now in [
                report(.adsbLol, hex: "aaa111", lat: 45.05, now: now),
                report(.adsbLol, hex: "bbb222", lat: 45.30, now: now),
                report(.adsbLol, hex: "ccc333", lat: 45.60, now: now),
            ] },
        ], enrichment: nil)
        store.start()
        defer { store.stop() }
        let ready = await eventually { store.aircraft.count == 3 }
        XCTAssertTrue(ready)

        XCTAssertEqual(store.focus?.id, "aaa111")  // nearest by default
        store.cycleSelection(1)
        XCTAssertEqual(store.focus?.id, "bbb222")
        store.cycleSelection(1)
        XCTAssertEqual(store.focus?.id, "ccc333")
        store.cycleSelection(1)
        XCTAssertEqual(store.focus?.id, "aaa111")  // wraps
        store.cycleSelection(-1)
        XCTAssertEqual(store.focus?.id, "ccc333")
    }

    func testWatchAlertFiresOnce() async {
        let store = AirspaceStore(config: .default, sources: [
            FakeSource(id: .adsbLol) { now in [report(.adsbLol, hex: "abc123", now: now)] },
        ], enrichment: nil)
        store.watchRules = [WatchRule(kind: .airline, value: "ACA", label: "Air Canada")]
        store.start()
        defer { store.stop() }
        let fired = await eventually { store.activeAlert != nil }
        XCTAssertTrue(fired)
        XCTAssertEqual(store.activeAlert?.rule.label, "Air Canada")
    }

    func testDisablingASourceRemovesItsAircraft() async {
        let store = AirspaceStore(config: .default, sources: [
            FakeSource(id: .adsbLol) { now in [report(.adsbLol, hex: "aaa111", now: now)] },
            FakeSource(id: .adsbFi) { now in [report(.adsbFi, hex: "bbb222", now: now)] },
        ], enrichment: nil)
        store.start()
        defer { store.stop() }
        let both = await eventually { store.aircraft.count == 2 }
        XCTAssertTrue(both)

        store.setSourceEnabled(.adsbFi, false)
        XCTAssertEqual(store.enabledSources, [.adsbLol, .openSky])
        XCTAssertEqual(store.aircraft.map(\.id), ["aaa111"])
        // A switched-off feed must not drag the health indicator down.
        let live = await eventually { store.feedHealth != .down }
        XCTAssertTrue(live)

        store.setSourceEnabled(.adsbFi, true)
        let back = await eventually { store.aircraft.count == 2 }
        XCTAssertTrue(back)
    }

    func testInjectedAircraftShowsUntilTheFeedsReportIt() async {
        let store = AirspaceStore(config: .default, sources: [], enrichment: nil)
        let ac = Aircraft(id: "feed01", callsign: "FAR1", latitude: 45, longitude: -75, altitudeFt: 30_000, groundSpeedKt: 400, trackDeg: 90,
                          positionTime: Date(), sources: [.adsbFi], agreement: .single)
        store.inject(ac)
        XCTAssertEqual(store.aircraft.map(\.id), ["feed01"])
        store.select("feed01", pin: true)
        XCTAssertEqual(store.focus?.id, "feed01")
    }

    func testStoreFilterAppliesImmediately() async {
        let store = AirspaceStore(config: .default, sources: [
            FakeSource(id: .adsbLol) { now in [report(.adsbLol, hex: "aaa111", now: now)] },
        ], enrichment: nil)
        store.start()
        defer { store.stop() }
        let ready = await eventually { store.aircraft.count == 1 }
        XCTAssertTrue(ready)
        var f = AircraftFilter()
        f.minAltitudeFt = 40_000   // the test aircraft flies at 30,000
        store.filter = f
        XCTAssertTrue(store.aircraft.isEmpty)
        store.filter = AircraftFilter()
        XCTAssertEqual(store.aircraft.count, 1)
    }

    func testMovingTheViewKeepsDataButJumpingClearsIt() async {
        let store = AirspaceStore(config: AirspaceConfig(name: "t", center: Coordinate(latitude: 45, longitude: -75), radiusNM: 40), sources: [
            FakeSource(id: .adsbLol) { now in [report(.adsbLol, hex: "aaa111", lat: 45.0, lon: -75.0, now: now)] },
        ], enrichment: nil)
        store.start()
        defer { store.stop() }
        let ready = await eventually { store.aircraft.count == 1 }
        XCTAssertTrue(ready)

        // A short hop keeps what's on screen while the feeds refetch.
        store.config = AirspaceConfig(name: "t", center: Coordinate(latitude: 45.2, longitude: -75), radiusNM: 40)
        XCTAssertEqual(store.aircraft.count, 1)
        // A long jump clears it.
        store.config = AirspaceConfig(name: "far", center: Coordinate(latitude: 10, longitude: 10), radiusNM: 40)
        XCTAssertTrue(store.aircraft.isEmpty)
    }
}
