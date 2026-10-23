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
    /// When the position fix was valid (not when it was downloaded).
    public var positionTime: Date

    public init(
        icao24: String, source: SourceID, callsign: String? = nil, registration: String? = nil,
        typeCode: String? = nil, latitude: Double, longitude: Double, altitudeFt: Double? = nil,
        groundSpeedKt: Double? = nil, trackDeg: Double? = nil, verticalRateFpm: Double? = nil,
        onGround: Bool = false, squawk: String? = nil, positionTime: Date
    ) {
        self.icao24 = icao24.lowercased()
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
        squawk: String? = nil, positionTime: Date, sources: [SourceID], agreement: Agreement,
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
        self.positionTime = positionTime
        self.sources = sources
        self.agreement = agreement
        self.altitudeDisputed = altitudeDisputed
        self.outlierSource = outlierSource
    }

    /// Sources whose reports were actually used (excludes an identified outlier).
    public var confirmingSources: Int { sources.count - (outlierSource == nil ? 0 : 1) }

    public var displayName: String { callsign ?? registration ?? id.uppercased() }

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
