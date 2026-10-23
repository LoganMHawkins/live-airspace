import XCTest
@testable import LiveAirspaceKit

final class EnrichmentTests: XCTestCase {
    func testParseAircraft() {
        let json = #"{"response":{"aircraft":{"type":"777 337ER","icao_type":"B77W","manufacturer":"Boeing","mode_s":"8004DF","registration":"VT-ALQ","registered_owner":"Air India","registered_owner_country_name":"India","url_photo":"https://image.airport-data.com/aircraft/001493356.jpg"}}}"#
        let d = EnrichmentService.parseAircraft(Data(json.utf8))
        XCTAssertEqual(d?.registration, "VT-ALQ")
        XCTAssertEqual(d?.typeName, "777 337ER")
        XCTAssertEqual(d?.operatorName, "Air India")
        XCTAssertEqual(d?.photoURL?.host, "image.airport-data.com")
    }

    func testParseRoute() {
        let json = #"{"response":{"flightroute":{"callsign_iata":"AI190","airline":{"name":"Air India"},"origin":{"iata_code":"YYZ","icao_code":"CYYZ","municipality":"Toronto","name":"Pearson","latitude":43.6772,"longitude":-79.6306},"destination":{"iata_code":"DEL","icao_code":"VIDP","municipality":"New Delhi","name":"Indira Gandhi","latitude":28.5665,"longitude":77.1031}}}}"#
        let d = EnrichmentService.parseRoute(Data(json.utf8))
        XCTAssertEqual(d?.airline, "Air India")
        XCTAssertEqual(d?.flightNumber, "AI190")
        XCTAssertEqual(d?.origin?.code, "YYZ")
        XCTAssertEqual(d?.destination?.city, "New Delhi")
    }

    func testUnknownAircraftIsNil() {
        XCTAssertNil(EnrichmentService.parseAircraft(Data(#"{"response":"unknown aircraft"}"#.utf8)))
        XCTAssertNil(EnrichmentService.parseRoute(Data(#"{"response":"unknown callsign"}"#.utf8)))
    }

    func testFlightNumberHeuristic() {
        XCTAssertTrue(EnrichmentService.looksLikeFlightNumber("ACA123"))
        XCTAssertTrue(EnrichmentService.looksLikeFlightNumber("WJA1234"))
        XCTAssertFalse(EnrichmentService.looksLikeFlightNumber("CGITS"))
        XCTAssertFalse(EnrichmentService.looksLikeFlightNumber("N123AB"))
        XCTAssertFalse(EnrichmentService.looksLikeFlightNumber("ABC"))
    }

    func testAirportDatabase() {
        XCTAssertGreaterThan(AirportDatabase.all.count, 3_000)
        let near = AirportDatabase.near(Coordinate(latitude: 51.47, longitude: -0.4543), radiusNM: 20)
        XCTAssertEqual(near.first?.code, "LHR")
        XCTAssertTrue(near.contains { $0.code == "LGW" } == false)  // ~25 nm away
    }
}
