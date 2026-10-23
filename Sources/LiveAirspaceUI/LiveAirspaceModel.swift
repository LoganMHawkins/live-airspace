import SwiftUI
import Combine
import LiveAirspaceKit

/// Ties settings, location and the data store together. Both the Apple TV app and the screen saver build one of these.
@MainActor
public final class LiveAirspaceModel: ObservableObject {
    public enum OpenSkyAccount: Equatable {
        case anonymous
        case checking
        case signedIn(clientID: String)
        case failed
    }

    @Published public private(set) var openSkyAccount: OpenSkyAccount = .anonymous
    public let settings: AppSettings
    public let store: AirspaceStore
    private let location = LocationProvider()
    private let allowsLocation: Bool
    private var cancellables: Set<AnyCancellable> = []
    private var fix: LocationProvider.Fix?
    private let sharesConfig: Bool

    /// - Parameter allowsLocation: false for the screen saver, which can't show a location permission prompt.
    /// - Parameters:
    ///   - sharesConfig: write the current airspace to the shared keychain group, for the Top Shelf extension.
    ///   - sources: replaces the default feeds (for tests).
    public init(defaults: UserDefaults = .standard, allowsLocation: Bool = true, sharesConfig: Bool = false, sources: [any AirspaceSource]? = nil) {
        self.sharesConfig = sharesConfig
        let settings = AppSettings(defaults: defaults)
        self.settings = settings
        self.allowsLocation = allowsLocation
        self.store = AirspaceStore(config: Self.config(for: settings.data, fix: nil), sources: sources ?? AirspaceStore.defaultSources())
        store.watchRules = settings.data.watchRules

        // @Published emits before the value changes, so pass the new value along instead of re-reading it.
        settings.$data
            .sink { [weak self] data in self?.apply(data) }
            .store(in: &cancellables)
        location.$fix
            .sink { [weak self] fix in self?.locationUpdated(fix) }
            .store(in: &cancellables)
        if allowsLocation, settings.data.place == .nearMe { location.request() }
        if let saved = OpenSkyCredentialStore.load() { openSkyAccount = .signedIn(clientID: saved.clientID) }
    }

    public var locationDenied: Bool { location.denied }

    /// Checks the OpenSky API client with OpenSky, and if it works saves it to the keychain and starts using it.
    public func saveOpenSky(clientID: String, clientSecret: String) async {
        let creds = OpenSkyCredentials(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                                       clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !creds.clientID.isEmpty, !creds.clientSecret.isEmpty else { return }
        openSkyAccount = .checking
        guard await creds.verify() else { openSkyAccount = .failed; return }
        OpenSkyCredentialStore.save(creds)
        store.setOpenSkyCredentials(creds)
        openSkyAccount = .signedIn(clientID: creds.clientID)
    }

    public func removeOpenSky() {
        OpenSkyCredentialStore.remove()
        store.setOpenSkyCredentials(nil)
        openSkyAccount = .anonymous
    }

    /// Play/Pause on the remote: Near me → each airport preset → back to Near me.
    public func cyclePlace() {
        let names = AirspaceConfig.presets.map(\.name)
        switch settings.data.place {
        case .nearMe: settings.data.place = .preset(names[0])
        case .preset(let name):
            if let i = names.firstIndex(of: name), i + 1 < names.count { settings.data.place = .preset(names[i + 1]) }
            else { settings.data.place = allowsLocation ? .nearMe : .preset(names[0]) }
        case .custom: settings.data.place = allowsLocation ? .nearMe : .preset(names[0])
        }
    }

    public func zoom(in zoomIn: Bool) {
        let r = settings.data.radiusNM * (zoomIn ? 0.75 : 1 / 0.75)
        settings.data.radiusNM = min(max(r.rounded(), 10), 150)
    }

    private func apply(_ d: SettingsData) {
        store.watchRules = d.watchRules
        if allowsLocation, d.place == .nearMe, fix == nil { location.request() }
        let config = Self.config(for: d, fix: fix)
        store.config = config
        if sharesConfig { SharedConfig.save(config) }
    }

    private func locationUpdated(_ fix: LocationProvider.Fix?) {
        self.fix = fix
        guard let fix, settings.data.place == .nearMe else { return }
        let name = fix.place.map { "Near \($0)" } ?? "Near you"
        settings.data.lastFix = AirspaceConfig(name: name, center: Coordinate(latitude: fix.latitude, longitude: fix.longitude), radiusNM: settings.data.radiusNM)
    }

    static func config(for d: SettingsData, fix: LocationProvider.Fix?) -> AirspaceConfig {
        var c: AirspaceConfig
        switch d.place {
        case .nearMe:
            if let fix {
                c = AirspaceConfig(name: fix.place.map { "Near \($0)" } ?? "Near you",
                                   center: Coordinate(latitude: fix.latitude, longitude: fix.longitude))
            } else {
                c = d.lastFix ?? .default
            }
        case .preset(let name):
            c = AirspaceConfig.presets.first { $0.name == name } ?? .default
        case .custom(let name, let lat, let lon):
            c = AirspaceConfig(name: name, center: Coordinate(latitude: lat, longitude: lon))
        }
        c.radiusNM = d.radiusNM
        return c
    }
}
