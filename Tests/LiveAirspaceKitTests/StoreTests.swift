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
}
