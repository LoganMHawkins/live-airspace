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
    /// The aircraft the camera is following, if any.
    @Published public private(set) var followID: String?
    /// Apple TV: arrow keys pan the map instead of stepping through aircraft.
    @Published public var exploring = false
    /// Set by menu commands (Mac) to open the search sheet or the settings window.
    @Published public var searchRequested = false

    public static let minRadiusNM = 5.0
    public static let maxRadiusNM = 250.0
    public let settings: AppSettings
    public let store: AirspaceStore
    private let location = LocationProvider()
    private let allowsLocation: Bool
    private var cancellables: Set<AnyCancellable> = []
    private var fix: LocationProvider.Fix?
    private let sharesConfig: Bool
    private var followTask: Task<Void, Never>?
    private var appliedDisabled: Set<SourceID> = []

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

    // MARK: where the radar is looking

    /// Switches to one of the user's own places (Settings, the Apple TV remote) and forgets any "return home" target.
    public func setPlace(_ place: Place) {
        stopFollowing()
        var d = settings.data
        d.place = place
        d.homePlace = nil
        settings.data = d
    }

    /// Play/Pause on the remote: Near me → each airport preset → back to Near me.
    public func cyclePlace() {
        let names = AirspaceConfig.presets.map(\.name)
        switch settings.data.homePlace ?? settings.data.place {
        case .nearMe: setPlace(.preset(names[0]))
        case .preset(let name):
            if let i = names.firstIndex(of: name), i + 1 < names.count { setPlace(.preset(names[i + 1])) }
            else { setPlace(allowsLocation ? .nearMe : .preset(names[0])) }
        case .custom: setPlace(allowsLocation ? .nearMe : .preset(names[0]))
        }
    }

    /// Looks somewhere else (a search result, a saved place, a map pan) while remembering where "home" is.
    public func goTo(_ coordinate: Coordinate, name: String, radiusNM: Double? = nil) {
        stopFollowing()
        applyView(center: coordinate, name: name, radius: radiusNM)
    }

    public func go(to saved: SavedPlace) {
        goTo(saved.coordinate, name: saved.name, radiusNM: saved.radiusNM)
    }

    private func applyView(center: Coordinate, name: String, radius: Double? = nil) {
        var d = settings.data
        if d.homePlace == nil { d.homePlace = d.place }
        d.place = .custom(name: name, latitude: center.latitude, longitude: center.longitude)
        if let radius { d.radiusNM = Self.clamp(radius) }
        settings.data = d
    }

    /// Back to the place the user chose, after panning, searching or following.
    public func recenter() {
        stopFollowing()
        var d = settings.data
        if let home = d.homePlace {
            d.place = home
            d.homePlace = nil
            settings.data = d
        }
    }

    public var isAwayFromHome: Bool { settings.data.homePlace != nil }

    /// Moves the view by a distance east and north (committing a drag, a scroll or an Apple TV remote press).
    public func pan(eastNM: Double, northNM: Double) {
        stopFollowing()
        let c = store.config.center
        let lat = min(max(c.latitude + northNM / 60, -85), 85)
        var lon = c.longitude + eastNM / (60 * max(cos(c.latitude * .pi / 180), 0.05))
        if lon > 180 { lon -= 360 } else if lon < -180 { lon += 360 }
        let target = Coordinate(latitude: lat, longitude: lon)
        applyView(center: target, name: Self.viewName(near: target))
    }

    /// One remote press while exploring: a quarter of the range in the pressed direction.
    public func panStep(dx: Int, dy: Int) {
        let step = store.config.radiusNM * 0.3
        pan(eastNM: Double(dx) * step, northNM: Double(-dy) * step)
    }

    public func setRadius(_ nm: Double) {
        settings.data.radiusNM = Self.clamp(nm.rounded())
    }

    public func zoom(in zoomIn: Bool) {
        setRadius(settings.data.radiusNM * (zoomIn ? 0.7 : 1 / 0.7))
    }

    /// Cycles through a few useful ranges (Apple TV remote, explore mode).
    public func cycleZoom() {
        let steps = [10.0, 20, 40, 80, 150, 250]
        let next = steps.first { $0 > settings.data.radiusNM + 0.5 } ?? steps[0]
        setRadius(next)
    }

    static func clamp(_ nm: Double) -> Double { min(max(nm, minRadiusNM), maxRadiusNM) }

    /// A short name for an arbitrary spot: the airport it is near, or just "Map view".
    static func viewName(near c: Coordinate) -> String {
        if let ap = AirportDatabase.near(c, radiusNM: 40).first { return "Near \(ap.code)" }
        return "Map view"
    }

    /// Where the camera is looking right now: the followed aircraft (so it stays centred between updates) or the view centre.
    public func cameraCenter(at date: Date) -> Coordinate {
        if let followID, let ac = store.aircraft.first(where: { $0.id == followID }) { return ac.position(at: date) }
        return store.config.center
    }

    // MARK: aircraft

    /// Jumps to an aircraft (a search result) and keeps the camera on it.
    public func showAircraft(_ ac: Aircraft) {
        store.inject(ac)
        follow(ac.id, at: ac.position(at: Date()), label: ac.displayName)
        if store.config.radiusNM > 60 { settings.data.radiusNM = 60 }
    }

    /// Follows an aircraft that is on screen.
    public func follow(_ id: String) {
        guard let ac = store.aircraft.first(where: { $0.id == id }) else { return }
        follow(id, at: ac.position(at: Date()), label: ac.displayName)
    }

    private func follow(_ id: String, at position: Coordinate, label: String) {
        followID = id
        applyView(center: position, name: "Following \(label)")
        store.select(id, pin: true, grace: 25)
        startFollowLoop()
    }

    public func stopFollowing() {
        followTask?.cancel()
        followTask = nil
        if let id = followID {
            followID = nil
            store.select(id)  // keep it selected, but let it revert to "nearest" after a while
        }
    }

    /// Re-centres the data feeds on the aircraft now and then, so the feeds keep covering it as it flies.
    private func startFollowLoop() {
        followTask?.cancel()
        followTask = Task { [weak self] in
            var missing = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let id = self.followID else { return }
                if let ac = self.store.aircraft.first(where: { $0.id == id }) {
                    missing = 0
                    let pos = ac.position(at: Date())
                    if Geo.distanceNM(pos, self.store.config.center) > self.store.config.radiusNM * 0.35 {
                        self.applyView(center: pos, name: "Following \(ac.displayName)")
                    }
                } else {
                    missing += 1
                    if missing > 20 { self.stopFollowing(); return }  // gone for 40 s
                }
            }
        }
    }

    // MARK: saved places and recents

    public func saveCurrentView(named name: String? = nil) {
        let c = store.config
        let title = name ?? (c.name.hasPrefix("Following") ? Self.viewName(near: c.center) : c.name)
        let place = SavedPlace(name: title, latitude: c.center.latitude, longitude: c.center.longitude, radiusNM: c.radiusNM)
        guard !settings.data.savedPlaces.contains(where: { $0.name == place.name && Geo.distanceNM($0.coordinate, place.coordinate) < 1 }) else { return }
        settings.data.savedPlaces.append(place)
    }

    public func deleteSavedPlace(_ id: UUID) {
        settings.data.savedPlaces.removeAll { $0.id == id }
    }

    public func addRecent(name: String, coordinate: Coordinate, radiusNM: Double = 40) {
        var recents = settings.data.recents.filter { !($0.name == name && Geo.distanceNM($0.coordinate, coordinate) < 1) }
        recents.insert(SavedPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude, radiusNM: radiusNM), at: 0)
        settings.data.recents = Array(recents.prefix(8))
    }

    public func clearRecents() { settings.data.recents = [] }

    // MARK: feeds and welcome

    public func isSourceEnabled(_ id: SourceID) -> Bool { !settings.data.disabledSources.contains(id) }

    public func setSource(_ id: SourceID, enabled: Bool) {
        var disabled = settings.data.disabledSources.filter { $0 != id }
        if !enabled { disabled.append(id) }
        settings.data.disabledSources = disabled
    }

    public func completeWelcome() { settings.data.hasSeenWelcome = true }
    public func showWelcomeAgain() { settings.data.hasSeenWelcome = false }

    /// Restores every setting to its default (the welcome screen stays dismissed).
    public func resetSettings() {
        stopFollowing()
        var fresh = SettingsData()
        fresh.hasSeenWelcome = true
        settings.data = fresh
    }

    private func apply(_ d: SettingsData) {
        store.watchRules = d.watchRules
        store.filter = d.filter
        let disabled = Set(d.disabledSources)
        if disabled != appliedDisabled {
            for id in SourceID.allCases where disabled.contains(id) != appliedDisabled.contains(id) { store.setSourceEnabled(id, !disabled.contains(id)) }
            appliedDisabled = disabled
        }
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
