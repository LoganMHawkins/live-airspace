import XCTest
@testable import LiveAirspaceKit

final class SearchTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func aircraft(_ id: String, callsign: String? = nil, reg: String? = nil, type: String? = nil, alt: Double? = 30_000,
                  onGround: Bool = false, sources: [SourceID] = [.adsbLol, .adsbFi]) -> Aircraft {
        Aircraft(id: id, callsign: callsign, registration: reg, typeCode: type, latitude: 45, longitude: -75, altitudeFt: alt,
                 groundSpeedKt: 400, trackDeg: 90, onGround: onGround, positionTime: now, sources: sources, agreement: sources.count > 1 ? .confirmed(spreadNM: 0.1) : .single)
    }

    // MARK: airports

    func testAirportCodeBeatsName() {
        XCTAssertEqual(SearchEngine.airports(matching: "lhr").first?.code, "LHR")
        XCTAssertEqual(SearchEngine.airports(matching: "EGLL").first?.code, "LHR")
    }

    func testAirportNameAndAccentInsensitivity() {
        XCTAssertTrue(SearchEngine.airports(matching: "heathrow").contains { $0.code == "LHR" })
        XCTAssertTrue(SearchEngine.airports(matching: "montreal").contains { $0.code == "YUL" })
        XCTAssertTrue(SearchEngine.airports(matching: "MONTRÉAL").contains { $0.code == "YUL" })
    }

    func testShortOrEmptyQueriesReturnNothing() {
        XCTAssertTrue(SearchEngine.airports(matching: "").isEmpty)
        XCTAssertTrue(SearchEngine.airports(matching: "l").isEmpty)
        XCTAssertTrue(SearchEngine.airports(matching: "qqqzzzxxx").isEmpty)
    }

    func testNearbyAirports() {
        let near = SearchEngine.nearbyAirports(to: Coordinate(latitude: 51.47, longitude: -0.4543), limit: 3)
        XCTAssertEqual(near.first?.code, "LHR")
        XCTAssertEqual(near.count, 3)
    }

    // MARK: aircraft on screen

    func testAircraftMatchingByCallsignRegistrationTypeAndHex() {
        let list = [aircraft("c01505", callsign: "ACA1040", reg: "C-FHYY", type: "BCS3"),
                    aircraft("abc123", callsign: "WJA77", reg: "C-GWSX", type: "B38M")]
        XCTAssertEqual(SearchEngine.aircraft(matching: "aca", in: list, details: [:]).map(\.id), ["c01505"])
        XCTAssertEqual(SearchEngine.aircraft(matching: "c-gwsx", in: list, details: [:]).map(\.id), ["abc123"])
        XCTAssertEqual(SearchEngine.aircraft(matching: "cgwsx", in: list, details: [:]).map(\.id), ["abc123"])
        XCTAssertEqual(SearchEngine.aircraft(matching: "b38m", in: list, details: [:]).map(\.id), ["abc123"])
        XCTAssertEqual(SearchEngine.aircraft(matching: "c01505", in: list, details: [:]).map(\.id), ["c01505"])
        XCTAssertTrue(SearchEngine.aircraft(matching: "zzz", in: list, details: [:]).isEmpty)
    }

    func testAircraftMatchingByRouteAndAirline() {
        var d = AircraftDetails()
        d.airline = "Air Canada"
        d.flightNumber = "AC1040"
        d.destination = AirportRef(iata: "YVR", icao: "CYVR", city: "Vancouver", name: "Vancouver International", coordinate: Coordinate(latitude: 49.19, longitude: -123.18))
        let list = [aircraft("c01505", callsign: "ACA1040"), aircraft("zzz999", callsign: "XYZ1")]
        XCTAssertEqual(SearchEngine.aircraft(matching: "yvr", in: list, details: ["c01505": d]).map(\.id), ["c01505"])
        XCTAssertEqual(SearchEngine.aircraft(matching: "air canada", in: list, details: ["c01505": d]).map(\.id), ["c01505"])
        XCTAssertEqual(SearchEngine.aircraft(matching: "ac1040", in: list, details: ["c01505": d]).map(\.id), ["c01505"])
        XCTAssertEqual(SearchEngine.aircraft(matching: "vancouver", in: list, details: ["c01505": d]).map(\.id), ["c01505"])
    }

    func testExactCallsignOutranksPrefix() {
        let list = [aircraft("a", callsign: "ACA1040X"), aircraft("b", callsign: "ACA1040")]
        XCTAssertEqual(SearchEngine.aircraft(matching: "ACA1040", in: list, details: [:]).first?.id, "b")
    }

    // MARK: lookup helpers, filter, models

    func testRegistrationShapes() {
        XCTAssertTrue(FeedLookup.looksLikeRegistration("C-GITS"))
        XCTAssertTrue(FeedLookup.looksLikeRegistration("N12345"))
        XCTAssertFalse(FeedLookup.looksLikeRegistration("ACA1040"))
        XCTAssertFalse(FeedLookup.looksLikeRegistration("NASA"))
    }

    func testAircraftFilter() {
        var f = AircraftFilter()
        XCTAssertTrue(f.isDefault)
        XCTAssertTrue(f.allows(aircraft("a")))
        XCTAssertFalse(f.allows(aircraft("g", onGround: true)))
        f.includeGround = true
        XCTAssertTrue(f.allows(aircraft("g", onGround: true)))
        f.minAltitudeFt = 10_000
        XCTAssertFalse(f.allows(aircraft("low", alt: 3_000)))
        XCTAssertTrue(f.allows(aircraft("hi", alt: 35_000)))
        f.maxAltitudeFt = 30_000
        XCTAssertFalse(f.allows(aircraft("hi", alt: 35_000)))
        f.onlyCrossChecked = true
        XCTAssertFalse(f.allows(aircraft("solo", alt: 20_000, sources: [.adsbLol])))
        XCTAssertTrue(f.allows(aircraft("pair", alt: 20_000)))
        XCTAssertFalse(f.isDefault)
    }

    func testFilterDecodesFromAnOlderPayload() throws {
        let f = try JSONDecoder().decode(AircraftFilter.self, from: Data(#"{"minAltitudeFt":5000}"#.utf8))
        XCTAssertEqual(f.minAltitudeFt, 5_000)
        XCTAssertEqual(f.maxAltitudeFt, 60_000)
        XCTAssertFalse(f.includeGround)
    }

    func testSavedPlaceRoundTrip() throws {
        let p = SavedPlace(name: "Cabin", latitude: 46.1, longitude: -74.2, radiusNM: 25)
        let back = try JSONDecoder().decode(SavedPlace.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.coordinate.latitude, 46.1)
    }

    func testCategoryDrivesIconSize() {
        var heli = aircraft("h"); heli.category = "A7"
        var heavy = aircraft("b"); heavy.category = "A5"
        var light = aircraft("l"); light.category = "A1"
        XCTAssertTrue(heli.isRotorcraft)
        XCTAssertGreaterThan(heavy.sizeFactor, 1)
        XCTAssertLessThan(light.sizeFactor, 1)
        XCTAssertEqual(aircraft("x").sizeFactor, 1)
    }

    func testReadsbParsesCategory() throws {
        let json = #"{"ac":[{"hex":"a1b2c3","flight":"HELI1","category":"A7","lat":45.0,"lon":-75.0,"alt_baro":1500,"seen_pos":1}]}"#
        let r = try ReadsbSource.parse(Data(json.utf8), source: .adsbFi, now: now)
        XCTAssertEqual(r.first?.category, "A7")
    }
}
