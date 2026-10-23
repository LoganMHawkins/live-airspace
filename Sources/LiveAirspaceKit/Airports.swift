import Foundation

public struct Airport: Sendable, Equatable {
    public var code: String
    public var icao: String
    public var name: String
    public var coordinate: Coordinate
    public var isLarge: Bool
}

public enum AirportDatabase {
    public static let all: [Airport] = {
        guard let data = AirportData.json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return rows.compactMap { r in
            guard r.count == 6, let code = r[0] as? String, let icao = r[1] as? String, let name = r[2] as? String,
                  let lat = (r[3] as? NSNumber)?.doubleValue, let lon = (r[4] as? NSNumber)?.doubleValue,
                  let size = (r[5] as? NSNumber)?.intValue else { return nil }
            return Airport(code: code, icao: icao, name: name, coordinate: Coordinate(latitude: lat, longitude: lon), isLarge: size == 1)
        }
    }()

    /// Airports within `radiusNM` of `center`, nearest first.
    public static func near(_ center: Coordinate, radiusNM: Double) -> [Airport] {
        all.filter { Geo.distanceNM(center, $0.coordinate) <= radiusNM }
            .sorted { Geo.distanceNM(center, $0.coordinate) < Geo.distanceNM(center, $1.coordinate) }
    }
}
