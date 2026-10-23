import Foundation

public struct AirportRef: Sendable, Equatable {
    public var iata: String?
    public var icao: String?
    public var city: String?
    public var name: String
    public var coordinate: Coordinate

    public var code: String { iata ?? icao ?? "—" }
}

/// Who and where an aircraft is, beyond what the ADS-B feeds carry.
public struct AircraftDetails: Sendable, Equatable {
    public var registration: String?
    public var typeName: String?
    public var manufacturer: String?
    public var operatorName: String?
    public var country: String?
    public var photoURL: URL?
    public var airline: String?
    public var flightNumber: String?
    public var origin: AirportRef?
    public var destination: AirportRef?

    public var isEmpty: Bool {
        registration == nil && typeName == nil && operatorName == nil && photoURL == nil && airline == nil && origin == nil
    }
}

/// Looks up aircraft and flight-route details from adsbdb.com, with caching and a polite request rate.
public actor EnrichmentService {
    private struct Entry<T> { var value: T?; var expires: Date }

    private var aircraftCache: [String: Entry<AircraftDetails>] = [:]
    private var routeCache: [String: Entry<AircraftDetails>] = [:]
    private var nextSlot = Date.distantPast
    private let spacing: TimeInterval = 0.4

    public init() {}

    public func details(hex: String, callsign: String?) async -> AircraftDetails {
        var result = AircraftDetails()
        if let info = await aircraftInfo(hex: hex) { result = info }
        if let callsign, Self.looksLikeFlightNumber(callsign), let route = await routeInfo(callsign: callsign) {
            result.airline = route.airline
            result.flightNumber = route.flightNumber
            result.origin = route.origin
            result.destination = route.destination
        }
        return result
    }

    /// Airline callsigns are three letters followed by digits (ACA123); anything else is likely a registration or private flight.
    static func looksLikeFlightNumber(_ callsign: String) -> Bool {
        let c = callsign.uppercased()
        guard c.count >= 4, c.count <= 8 else { return false }
        return c.prefix(3).allSatisfy(\.isLetter) && c.dropFirst(3).first?.isNumber == true
    }

    private func aircraftInfo(hex: String) async -> AircraftDetails? {
        let key = hex.lowercased()
        if let e = aircraftCache[key], e.expires > Date() { return e.value }
        let value = await fetch("https://api.adsbdb.com/v0/aircraft/\(key)", parse: Self.parseAircraft)
        aircraftCache[key] = Entry(value: value, expires: Date().addingTimeInterval(value == nil ? 600 : 86_400))
        return value
    }

    private func routeInfo(callsign: String) async -> AircraftDetails? {
        let key = callsign.uppercased()
        if let e = routeCache[key], e.expires > Date() { return e.value }
        let value = await fetch("https://api.adsbdb.com/v0/callsign/\(key)", parse: Self.parseRoute)
        routeCache[key] = Entry(value: value, expires: Date().addingTimeInterval(value == nil ? 600 : 1_800))
        return value
    }

    private func fetch(_ urlString: String, parse: (Data) -> AircraftDetails?) async -> AircraftDetails? {
        guard let url = URL(string: urlString) else { return nil }
        // Serialise lookups so a busy sky doesn't hammer a free service.
        let slot = max(nextSlot, Date())
        nextSlot = slot.addingTimeInterval(spacing)
        let wait = slot.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard let data = try? await HTTP.get(url) else { return nil }
        return parse(data)
    }

    // MARK: parsing

    static func parseAircraft(_ data: Data) -> AircraftDetails? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["response"] as? [String: Any],
              let ac = response["aircraft"] as? [String: Any] else { return nil }
        func str(_ k: String) -> String? { (ac[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return AircraftDetails(
            registration: str("registration"), typeName: str("type"), manufacturer: str("manufacturer"),
            operatorName: str("registered_owner"), country: str("registered_owner_country_name"),
            photoURL: str("url_photo").flatMap(URL.init(string:)))
    }

    static func parseRoute(_ data: Data) -> AircraftDetails? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["response"] as? [String: Any],
              let route = response["flightroute"] as? [String: Any] else { return nil }
        func airport(_ any: Any?) -> AirportRef? {
            guard let a = any as? [String: Any], let name = a["name"] as? String,
                  let lat = (a["latitude"] as? NSNumber)?.doubleValue, let lon = (a["longitude"] as? NSNumber)?.doubleValue
            else { return nil }
            return AirportRef(iata: a["iata_code"] as? String, icao: a["icao_code"] as? String,
                              city: a["municipality"] as? String, name: name,
                              coordinate: Coordinate(latitude: lat, longitude: lon))
        }
        return AircraftDetails(
            airline: (route["airline"] as? [String: Any])?["name"] as? String,
            flightNumber: route["callsign_iata"] as? String,
            origin: airport(route["origin"]), destination: airport(route["destination"]))
    }
}
