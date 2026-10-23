import XCTest
import LiveAirspaceKit
@testable import LiveAirspaceUI

@MainActor
final class SettingsTests: XCTestCase {
    func testUnits() {
        XCTAssertEqual(Units.aviation.altitude(35_000), "FL350")
        XCTAssertEqual(Units.aviation.altitude(4_980), "5000 ft")
        XCTAssertEqual(Units.metric.altitude(10_000), "3050 m")
        XCTAssertEqual(Units.metric.speed(100), "185 km/h")
        XCTAssertEqual(Units.aviation.distance(12.34), "12.3 nm")
        XCTAssertEqual(Units.metric.distance(10), "18.5 km")
    }

    func testSettingsRoundTripThroughDefaults() throws {
        let suite = "liveairspace.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.data.place, .nearMe)  // default
        settings.data.place = .custom(name: "Cabin", latitude: 46.1, longitude: -74.2)
        settings.data.radiusNM = 60
        settings.data.display.units = .metric
        settings.data.watchRules = [WatchRule(kind: .type, value: "a388", label: "A380")]

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.data, settings.data)
        XCTAssertEqual(reloaded.data.watchRules.first?.value, "A388")  // normalised to upper case
    }

    func testConfigResolution() {
        var d = SettingsData()
        d.radiusNM = 25

        d.place = .preset("London LHR")
        let preset = LiveAirspaceModel.config(for: d, fix: nil)
        XCTAssertEqual(preset.name, "London LHR")
        XCTAssertEqual(preset.radiusNM, 25)

        d.place = .nearMe
        XCTAssertEqual(LiveAirspaceModel.config(for: d, fix: nil).name, AirspaceConfig.default.name)  // nothing known yet
        d.lastFix = AirspaceConfig(name: "Near Perth", center: Coordinate(latitude: 44.9, longitude: -76.2))
        XCTAssertEqual(LiveAirspaceModel.config(for: d, fix: nil).name, "Near Perth")  // falls back to the last fix
        let fresh = LiveAirspaceModel.config(for: d, fix: .init(latitude: 43.7, longitude: -79.4, place: "Toronto"))
        XCTAssertEqual(fresh.name, "Near Toronto")
        XCTAssertEqual(fresh.center.latitude, 43.7, accuracy: 0.001)

        d.place = .custom(name: "Cabin", latitude: 46.1, longitude: -74.2)
        XCTAssertEqual(LiveAirspaceModel.config(for: d, fix: nil).center.longitude, -74.2, accuracy: 0.001)
    }
}
