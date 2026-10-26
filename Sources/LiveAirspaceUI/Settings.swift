import SwiftUI
import LiveAirspaceKit

public enum LabelMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case all = "All aircraft", nearest = "Nearest 5", off = "Off"
    public var id: String { rawValue }
}

public enum MapStyleChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case dark = "Dark", light = "Light", satellite = "Satellite"
    public var id: String { rawValue }
}

public enum Units: String, Codable, CaseIterable, Sendable, Identifiable {
    case aviation = "Aviation (ft, kt, nm)", metric = "Metric (m, km/h, km)"
    public var id: String { rawValue }

    func altitude(_ ft: Double) -> String {
        switch self {
        case .aviation: return ft >= 18_000 ? "FL\(Int((ft / 100).rounded()))" : "\(Int((ft / 100).rounded()) * 100) ft"
        case .metric: return "\(Int((ft * 0.3048 / 10).rounded()) * 10) m"
        }
    }
    func speed(_ kt: Double) -> String {
        switch self {
        case .aviation: return "\(Int(kt)) kt"
        case .metric: return "\(Int(kt * 1.852)) km/h"
        }
    }
    func distance(_ nm: Double) -> String {
        switch self {
        case .aviation: return String(format: "%.1f nm", nm)
        case .metric: return String(format: "%.1f km", nm * 1.852)
        }
    }
    func rate(_ fpm: Double) -> String {
        switch self {
        case .aviation: return "\(Int(abs(fpm))) fpm"
        case .metric: return String(format: "%.1f m/s", abs(fpm) * 0.00508)
        }
    }
}

public enum Place: Codable, Equatable, Sendable {
    case nearMe
    case preset(String)
    case custom(name: String, latitude: Double, longitude: Double)
}

public struct DisplaySettings: Codable, Equatable, Sendable {
    public var mapOpacity = 0.7
    public var mapStyle = MapStyleChoice.dark
    public var showAirports = true
    public var showTrails = true
    public var labels = LabelMode.all
    public var units = Units.aviation
    /// iPhone/iPad only: stop the screen sleeping while the radar is showing.
    public var keepAwake = false

    public init() {}

    // Settings written by an older version lack newer keys; fall back to defaults instead of discarding everything.
    enum CodingKeys: String, CodingKey { case mapOpacity, mapStyle, lightMap, showAirports, showTrails, labels, units, keepAwake }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mapOpacity = try c.decodeIfPresent(Double.self, forKey: .mapOpacity) ?? 0.7
        // Earlier versions only had a light/dark switch.
        let legacyLight = try c.decodeIfPresent(Bool.self, forKey: .lightMap) ?? false
        mapStyle = try c.decodeIfPresent(MapStyleChoice.self, forKey: .mapStyle) ?? (legacyLight ? .light : .dark)
        showAirports = try c.decodeIfPresent(Bool.self, forKey: .showAirports) ?? true
        showTrails = try c.decodeIfPresent(Bool.self, forKey: .showTrails) ?? true
        labels = try c.decodeIfPresent(LabelMode.self, forKey: .labels) ?? .all
        units = try c.decodeIfPresent(Units.self, forKey: .units) ?? .aviation
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mapOpacity, forKey: .mapOpacity)
        try c.encode(mapStyle, forKey: .mapStyle)
        try c.encode(showAirports, forKey: .showAirports)
        try c.encode(showTrails, forKey: .showTrails)
        try c.encode(labels, forKey: .labels)
        try c.encode(units, forKey: .units)
        try c.encode(keepAwake, forKey: .keepAwake)
    }
}

public struct SettingsData: Codable, Equatable, Sendable {
    public var place = Place.nearMe
    public var radiusNM = 40.0
    public var display = DisplaySettings()
    public var watchRules: [WatchRule] = []
    /// Last location fix, so "Near me" has somewhere sensible to start before the next fix arrives.
    public var lastFix: AirspaceConfig?
    /// Where "return home" goes after the user pans, searches or follows an aircraft away from their chosen place.
    public var homePlace: Place?
    public var savedPlaces: [SavedPlace] = []
    /// Most recent search choices, newest first.
    public var recents: [SavedPlace] = []
    public var disabledSources: [SourceID] = []
    public var filter = AircraftFilter()
    public var hasSeenWelcome = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case place, radiusNM, display, watchRules, lastFix, homePlace, savedPlaces, recents, disabledSources, filter, hasSeenWelcome
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        place = try c.decodeIfPresent(Place.self, forKey: .place) ?? .nearMe
        radiusNM = try c.decodeIfPresent(Double.self, forKey: .radiusNM) ?? 40
        display = try c.decodeIfPresent(DisplaySettings.self, forKey: .display) ?? DisplaySettings()
        watchRules = try c.decodeIfPresent([WatchRule].self, forKey: .watchRules) ?? []
        lastFix = try c.decodeIfPresent(AirspaceConfig.self, forKey: .lastFix)
        homePlace = try c.decodeIfPresent(Place.self, forKey: .homePlace)
        savedPlaces = try c.decodeIfPresent([SavedPlace].self, forKey: .savedPlaces) ?? []
        recents = try c.decodeIfPresent([SavedPlace].self, forKey: .recents) ?? []
        disabledSources = try c.decodeIfPresent([SourceID].self, forKey: .disabledSources) ?? []
        filter = try c.decodeIfPresent(AircraftFilter.self, forKey: .filter) ?? AircraftFilter()
        // Everyone sees the welcome once, including people updating from an earlier version.
        hasSeenWelcome = try c.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome) ?? false
    }
}

/// Persisted user settings. The Apple TV app uses standard defaults; the screen saver uses its module defaults.
@MainActor
public final class AppSettings: ObservableObject {
    @Published public var data: SettingsData {
        didSet { if data != oldValue { save() } }
    }
    private let defaults: UserDefaults
    private static let key = "liveAirspace.settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.data = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(SettingsData.self, from: $0) } ?? SettingsData()
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(data) { defaults.set(encoded, forKey: Self.key) }
    }
}
