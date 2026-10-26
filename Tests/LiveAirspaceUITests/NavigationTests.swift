import XCTest
import LiveAirspaceKit
@testable import LiveAirspaceUI

@MainActor
final class NavigationTests: XCTestCase {
    private func makeModel() throws -> (LiveAirspaceModel, UserDefaults, String) {
        let suite = "liveairspace.nav.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = LiveAirspaceModel(defaults: defaults, allowsLocation: false, sources: [])
        model.setPlace(.preset("London LHR"))
        return (model, defaults, suite)
    }

    func testPanMovesTheViewAndRememberingHome() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = model.store.config.center
        XCTAssertFalse(model.isAwayFromHome)

        model.pan(eastNM: 60, northNM: 0)
        let moved = model.store.config.center
        // 60 nm east at 51.5°N is 1/(cos 51.5°) degrees of longitude.
        XCTAssertEqual(moved.longitude - start.longitude, 1.0 / cos(start.latitude * .pi / 180), accuracy: 0.02)
        XCTAssertEqual(moved.latitude, start.latitude, accuracy: 0.001)
        XCTAssertTrue(model.isAwayFromHome)

        model.pan(eastNM: 0, northNM: 30)
        XCTAssertEqual(model.store.config.center.latitude, start.latitude + 0.5, accuracy: 0.01)

        model.recenter()
        XCTAssertFalse(model.isAwayFromHome)
        XCTAssertEqual(model.store.config.name, "London LHR")
        XCTAssertEqual(model.store.config.center.latitude, start.latitude, accuracy: 0.0001)
    }

    func testGoToKeepsTheOriginalHomeAcrossSeveralMoves() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.goTo(Coordinate(latitude: 40.64, longitude: -73.78), name: "JFK Airport", radiusNM: 25)
        model.goTo(Coordinate(latitude: 49.19, longitude: -123.18), name: "YVR Airport", radiusNM: 25)
        XCTAssertEqual(model.store.config.name, "YVR Airport")
        XCTAssertEqual(model.store.config.radiusNM, 25)
        model.recenter()
        XCTAssertEqual(model.store.config.name, "London LHR")  // not JFK
    }

    func testChoosingAPlaceInSettingsForgetsTheAwayState() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.pan(eastNM: 20, northNM: 0)
        XCTAssertTrue(model.isAwayFromHome)
        model.setPlace(.preset("Toronto YYZ"))
        XCTAssertFalse(model.isAwayFromHome)
        XCTAssertEqual(model.store.config.name, "Toronto YYZ")
    }

    func testZoomIsClamped() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        for _ in 0..<20 { model.zoom(in: true) }
        XCTAssertEqual(model.settings.data.radiusNM, LiveAirspaceModel.minRadiusNM)
        for _ in 0..<30 { model.zoom(in: false) }
        XCTAssertEqual(model.settings.data.radiusNM, LiveAirspaceModel.maxRadiusNM)
        model.setRadius(9_999)
        XCTAssertEqual(model.settings.data.radiusNM, LiveAirspaceModel.maxRadiusNM)
    }

    func testCycleZoomStepsThroughUsefulRanges() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setRadius(40)
        model.cycleZoom(); XCTAssertEqual(model.settings.data.radiusNM, 80)
        model.cycleZoom(); XCTAssertEqual(model.settings.data.radiusNM, 150)
        model.cycleZoom(); XCTAssertEqual(model.settings.data.radiusNM, 250)
        model.cycleZoom(); XCTAssertEqual(model.settings.data.radiusNM, 10)  // wraps
    }

    func testShowingAnAircraftFollowsIt() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ac = Aircraft(id: "c01505", callsign: "ACA1040", latitude: 43.7, longitude: -79.6, altitudeFt: 20_000, groundSpeedKt: 0, trackDeg: 0,
                          positionTime: Date(), sources: [.adsbFi], agreement: .single)
        model.showAircraft(ac)
        XCTAssertEqual(model.followID, "c01505")
        XCTAssertEqual(model.store.focus?.id, "c01505")
        XCTAssertEqual(model.store.config.center.latitude, 43.7, accuracy: 0.01)
        XCTAssertTrue(model.store.config.name.hasPrefix("Following"))
        XCTAssertTrue(model.isAwayFromHome)
        XCTAssertEqual(model.cameraCenter(at: Date()).latitude, 43.7, accuracy: 0.01)

        model.stopFollowing()
        XCTAssertNil(model.followID)
        model.recenter()
        XCTAssertEqual(model.store.config.name, "London LHR")
    }

    func testSavedPlacesAndRecents() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.saveCurrentView()
        model.saveCurrentView()  // same spot, same name: no duplicate
        XCTAssertEqual(model.settings.data.savedPlaces.count, 1)
        let saved = try XCTUnwrap(model.settings.data.savedPlaces.first)
        XCTAssertEqual(saved.name, "London LHR")

        model.goTo(Coordinate(latitude: 10, longitude: 10), name: "Elsewhere")
        model.go(to: saved)
        XCTAssertEqual(model.store.config.center.latitude, saved.latitude, accuracy: 0.0001)

        model.deleteSavedPlace(saved.id)
        XCTAssertTrue(model.settings.data.savedPlaces.isEmpty)

        for i in 0..<12 { model.addRecent(name: "Place \(i)", coordinate: Coordinate(latitude: Double(i) * 5, longitude: 0)) }
        XCTAssertEqual(model.settings.data.recents.count, 8)
        XCTAssertEqual(model.settings.data.recents.first?.name, "Place 11")
        model.addRecent(name: "Place 11", coordinate: Coordinate(latitude: 55, longitude: 0))  // repeat moves to front without duplicating
        XCTAssertEqual(model.settings.data.recents.filter { $0.name == "Place 11" }.count, 1)
        model.clearRecents()
        XCTAssertTrue(model.settings.data.recents.isEmpty)
    }

    func testFeedTogglesReachTheStore() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(model.isSourceEnabled(.openSky))
        model.setSource(.openSky, enabled: false)
        XCTAssertFalse(model.isSourceEnabled(.openSky))
        XCTAssertFalse(model.store.enabledSources.contains(.openSky))
        model.setSource(.openSky, enabled: true)
        XCTAssertTrue(model.store.enabledSources.contains(.openSky))
    }

    func testFilterSettingReachesTheStore() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.settings.data.filter.onlyCrossChecked = true
        XCTAssertTrue(model.store.filter.onlyCrossChecked)
    }

    func testWelcomeFlag() throws {
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(model.settings.data.hasSeenWelcome)
        model.completeWelcome()
        XCTAssertTrue(model.settings.data.hasSeenWelcome)
        model.showWelcomeAgain()
        XCTAssertFalse(model.settings.data.hasSeenWelcome)
        model.settings.data.radiusNM = 99
        model.resetSettings()
        XCTAssertEqual(model.settings.data.radiusNM, 40)
        XCTAssertTrue(model.settings.data.hasSeenWelcome)  // resetting doesn't bring the welcome screen back
    }

    func testViewNamesUseTheNearestAirport() {
        XCTAssertEqual(LiveAirspaceModel.viewName(near: Coordinate(latitude: 51.47, longitude: -0.45)), "Near LHR")
        XCTAssertEqual(LiveAirspaceModel.viewName(near: Coordinate(latitude: 0, longitude: -30)), "Map view")  // mid-Atlantic
    }

    func testLegacyLightMapSettingMigrates() throws {
        let old = #"{"display":{"lightMap":true,"mapOpacity":0.5}}"#
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.display.mapStyle, .light)
        let dark = try JSONDecoder().decode(SettingsData.self, from: Data(#"{"display":{"mapOpacity":0.5}}"#.utf8))
        XCTAssertEqual(dark.display.mapStyle, .dark)
        let sat = try JSONDecoder().decode(SettingsData.self, from: Data(#"{"display":{"mapStyle":"Satellite"}}"#.utf8))
        XCTAssertEqual(sat.display.mapStyle, .satellite)
    }
}
