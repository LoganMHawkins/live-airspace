import Foundation

public struct Coordinate: Sendable, Equatable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum SourceID: String, Sendable, CaseIterable, Codable, Comparable {
    case adsbLol = "adsb.lol"
    case adsbFi = "adsb.fi"
    case openSky = "OpenSky"

    /// Declaration order, so readsb feeds list before OpenSky.
    public static func < (lhs: SourceID, rhs: SourceID) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One source's view of one aircraft, before cross-referencing.
public struct SourceReport: Sendable, Equatable {
    public var icao24: String
    public var source: SourceID
    public var callsign: String?
    public var registration: String?
    public var typeCode: String?
    public var latitude: Double
    public var longitude: Double
    public var altitudeFt: Double?
    public var groundSpeedKt: Double?
    public var trackDeg: Double?
    public var verticalRateFpm: Double?
    public var onGround: Bool
    public var squawk: String?
    /// ADS-B emitter category (A1 light … A5 heavy, A7 rotorcraft, B* balloon/glider/UAV…), when the feed provides it.
    public var category: String?
    /// When the position fix was valid (not when it was downloaded).
    public var positionTime: Date

    public init(
        icao24: String, source: SourceID, callsign: String? = nil, registration: String? = nil,
        typeCode: String? = nil, latitude: Double, longitude: Double, altitudeFt: Double? = nil,
        groundSpeedKt: Double? = nil, trackDeg: Double? = nil, verticalRateFpm: Double? = nil,
        onGround: Bool = false, squawk: String? = nil, category: String? = nil, positionTime: Date
    ) {
        self.icao24 = icao24.lowercased()
        self.category = category
        self.source = source
        self.callsign = callsign
        self.registration = registration
        self.typeCode = typeCode
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeFt = altitudeFt
        self.groundSpeedKt = groundSpeedKt
        self.trackDeg = trackDeg
        self.verticalRateFpm = verticalRateFpm
        self.onGround = onGround
        self.squawk = squawk
        self.positionTime = positionTime
    }
}

/// How well independent sources agree about an aircraft.
public enum Agreement: Sendable, Equatable {
    /// Seen by one source only; nothing to check it against.
    case single
    /// Two or more sources agree on position (largest gap, in nautical miles).
    case confirmed(spreadNM: Double)
    /// Sources disagree on position by more than the tolerance.
    case disputed(spreadNM: Double)

    public var isDisputed: Bool {
        if case .disputed = self { return true }
        return false
    }
}

/// An aircraft after cross-referencing every source that saw it.
public struct Aircraft: Identifiable, Sendable, Equatable {
    public var id: String
    public var callsign: String?
    public var registration: String?
    public var typeCode: String?
    public var latitude: Double
    public var longitude: Double
    public var altitudeFt: Double?
    public var groundSpeedKt: Double?
    public var trackDeg: Double?
    public var verticalRateFpm: Double?
    public var onGround: Bool
    public var squawk: String?
    public var category: String?
    public var positionTime: Date
    public var sources: [SourceID]
    public var agreement: Agreement
    /// True when sources report barometric altitudes that differ by more than the tolerance.
    public var altitudeDisputed: Bool
    /// When 3+ sources saw it and one disagreed with the rest, the odd one out (its report is ignored).
    public var outlierSource: SourceID?

    public init(
        id: String, callsign: String? = nil, registration: String? = nil, typeCode: String? = nil,
        latitude: Double, longitude: Double, altitudeFt: Double? = nil, groundSpeedKt: Double? = nil,
        trackDeg: Double? = nil, verticalRateFpm: Double? = nil, onGround: Bool = false,
        squawk: String? = nil, category: String? = nil, positionTime: Date, sources: [SourceID], agreement: Agreement,
        altitudeDisputed: Bool = false, outlierSource: SourceID? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.registration = registration
        self.typeCode = typeCode
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeFt = altitudeFt
        self.groundSpeedKt = groundSpeedKt
        self.trackDeg = trackDeg
        self.verticalRateFpm = verticalRateFpm
        self.onGround = onGround
        self.squawk = squawk
        self.category = category
        self.positionTime = positionTime
        self.sources = sources
        self.agreement = agreement
        self.altitudeDisputed = altitudeDisputed
        self.outlierSource = outlierSource
    }

    /// Sources whose reports were actually used (excludes an identified outlier).
    public var confirmingSources: Int { sources.count - (outlierSource == nil ? 0 : 1) }

    public var displayName: String { callsign ?? registration ?? id.uppercased() }

    public var isRotorcraft: Bool { category == "A7" }

    /// Relative icon size: light aircraft smaller, heavies larger.
    public var sizeFactor: Double {
        switch category {
        case "A1": return 0.75
        case "A2": return 0.85
        case "A4": return 1.05
        case "A5": return 1.2
        case "A7": return 0.9
        case .some(let c) where c.hasPrefix("B"): return 0.8
        default: return 1
        }
    }

    /// Dead-reckoned position at `date`, so motion stays smooth between polls.
    public func position(at date: Date, maxExtrapolation: TimeInterval = 90) -> Coordinate {
        guard !onGround, let speed = groundSpeedKt, let track = trackDeg else {
            return Coordinate(latitude: latitude, longitude: longitude)
        }
        let dt = min(max(date.timeIntervalSince(positionTime), 0), maxExtrapolation)
        return Geo.project(
            Coordinate(latitude: latitude, longitude: longitude),
            trackDeg: track, distanceNM: speed * dt / 3600
        )
    }
}

public struct AirspaceConfig: Sendable, Equatable, Codable {
    public var name: String
    public var center: Coordinate
    public var radiusNM: Double

    public init(name: String, center: Coordinate, radiusNM: Double = 40) {
        self.name = name
        self.center = center
        self.radiusNM = radiusNM
    }

    public static let presets: [AirspaceConfig] = [
        .init(name: "Ottawa YOW", center: .init(latitude: 45.3225, longitude: -75.6692)),
        .init(name: "Toronto YYZ", center: .init(latitude: 43.6777, longitude: -79.6248)),
        .init(name: "Vancouver YVR", center: .init(latitude: 49.1967, longitude: -123.1815)),
        .init(name: "Montréal YUL", center: .init(latitude: 45.4706, longitude: -73.7408)),
        .init(name: "New York JFK", center: .init(latitude: 40.6413, longitude: -73.7781)),
        .init(name: "London LHR", center: .init(latitude: 51.4700, longitude: -0.4543)),
        .init(name: "Los Angeles LAX", center: .init(latitude: 33.9416, longitude: -118.4085)),
    ]

    public static let `default` = presets[0]
}


/// A place the user has saved (from Search or Settings) to jump back to.
public struct SavedPlace: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var radiusNM: Double

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, radiusNM: Double = 40) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusNM = radiusNM
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

/// Which aircraft the display shows.
public struct AircraftFilter: Codable, Equatable, Sendable {
    /// Hide anything below this altitude (feet). 0 shows everything.
    public var minAltitudeFt: Double = 0
    /// Hide anything above this altitude (feet).
    public var maxAltitudeFt: Double = 60_000
    public var includeGround = false
    public var onlyCrossChecked = false

    public init() {}

    enum CodingKeys: String, CodingKey { case minAltitudeFt, maxAltitudeFt, includeGround, onlyCrossChecked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minAltitudeFt = try c.decodeIfPresent(Double.self, forKey: .minAltitudeFt) ?? 0
        maxAltitudeFt = try c.decodeIfPresent(Double.self, forKey: .maxAltitudeFt) ?? 60_000
        includeGround = try c.decodeIfPresent(Bool.self, forKey: .includeGround) ?? false
        onlyCrossChecked = try c.decodeIfPresent(Bool.self, forKey: .onlyCrossChecked) ?? false
    }

    public var isDefault: Bool { self == AircraftFilter() }

    public func allows(_ ac: Aircraft) -> Bool {
        if ac.onGround { return includeGround }
        if onlyCrossChecked && ac.confirmingSources < 2 { return false }
        if let alt = ac.altitudeFt, alt < minAltitudeFt || alt > maxAltitudeFt { return false }
        return true
    }
}
