import SwiftUI
import LiveAirspaceKit

public enum LabelMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case all = "All aircraft", nearest = "Nearest 5", off = "Off"
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
    public var lightMap = false
    public var showAirports = true
    public var showTrails = true
    public var labels = LabelMode.all
    public var units = Units.aviation

    public init() {}
}

public struct SettingsData: Codable, Equatable, Sendable {
    public var place = Place.nearMe
    public var radiusNM = 40.0
    public var display = DisplaySettings()
    public var watchRules: [WatchRule] = []
    /// Last location fix, so "Near me" has somewhere sensible to start before the next fix arrives.
    public var lastFix: AirspaceConfig?

    public init() {}
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
