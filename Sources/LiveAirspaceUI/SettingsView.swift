import SwiftUI
import LiveAirspaceKit
#if canImport(UIKit)
import UIKit
#endif

/// Settings for the Apple TV, iPhone, iPad and Mac apps and the Mac screen saver.
public struct SettingsView: View {
    @ObservedObject var model: LiveAirspaceModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: AirspaceStore
    var allowsNearMe: Bool
    var onDone: () -> Void
    var onShowWelcome: (() -> Void)?

    @State private var customWatch = ""
    @State private var customWatchKind = WatchRule.Kind.airline
    @State private var openSkyID = ""
    @State private var openSkySecret = ""
    @State private var latText = ""
    @State private var lonText = ""
    @State private var confirmReset = false
    @Environment(\.openURL) private var openURL

    public init(model: LiveAirspaceModel, allowsNearMe: Bool = true, onShowWelcome: (() -> Void)? = nil, onDone: @escaping () -> Void) {
        self.model = model
        self.settings = model.settings
        self.store = model.store
        self.allowsNearMe = allowsNearMe
        self.onShowWelcome = onShowWelcome
        self.onDone = onDone
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                locationCard
                mapCard
                aircraftCard
                feedsCard
                alertsCard
                savedPlacesCard
                #if os(iOS)
                deviceCard
                #endif
                aboutCard
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            if case .custom(_, let lat, let lon) = settings.data.place { latText = String(lat); lonText = String(lon) }
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.primary)
            Spacer()
            Button(action: onDone) { Text("Done").foregroundStyle(.black.opacity(0.85)) }.accentButton().controlSize(.large)
        }
    }

    // MARK: location

    private var placeChoice: Binding<String> {
        Binding {
            switch settings.data.homePlace ?? settings.data.place {
            case .nearMe: return "nearMe"
            case .preset(let n): return "preset:\(n)"
            case .custom: return "custom"
            }
        } set: { v in
            if v == "nearMe" { model.setPlace(.nearMe) }
            else if v == "custom" {
                let c = Double(latText).flatMap { lat in Double(lonText).map { (lat, $0) } } ?? (store.config.center.latitude, store.config.center.longitude)
                latText = String(c.0); lonText = String(c.1)
                model.setPlace(.custom(name: "Custom", latitude: c.0, longitude: c.1))
            } else { model.setPlace(.preset(String(v.dropFirst("preset:".count)))) }
        }
    }

    private var locationCard: some View {
        SettingsCard(title: "Location", symbol: "location") {
            Picker("Centre on", selection: placeChoice) {
                if allowsNearMe { Text("Near me").tag("nearMe") }
                ForEach(AirspaceConfig.presets, id: \.name) { Text($0.name).tag("preset:\($0.name)") }
                Text("Custom coordinates").tag("custom")
            }
            .font(.system(.body, design: .rounded, weight: .medium))
            if case .custom = settings.data.homePlace ?? settings.data.place {
                TextField("Latitude (e.g. 45.32)", text: $latText).onSubmit(applyCustom)
                TextField("Longitude (e.g. -75.67)", text: $lonText).onSubmit(applyCustom)
            }
            if allowsNearMe, model.locationDenied {
                Text("Location access is off, so Near me can't work. Turn it on for Live Airspace in system settings.").settingsFootnote()
            }
            SegmentedChoice(title: "Range", symbol: "scope", selection: $settings.data.radiusNM,
                            options: [10.0, 20, 40, 80, 150, 250].map { (settings.data.display.units.distance($0).replacingOccurrences(of: ".0", with: ""), $0) })
            if model.isAwayFromHome {
                Button { model.recenter() } label: { Label("Return to home view", systemImage: "house") }
            }
            Button { model.saveCurrentView() } label: { Label("Save this view", systemImage: "bookmark") }
            Text("Pan, zoom, search or follow an aircraft to look anywhere in the world; Return to home goes back to this place.").settingsFootnote()
        }
    }

    private func applyCustom() {
        guard let lat = Double(latText), let lon = Double(lonText), (-90...90).contains(lat), (-180...180).contains(lon) else { return }
        model.setPlace(.custom(name: "Custom", latitude: lat, longitude: lon))
    }

    // MARK: map

    private var mapCard: some View {
        SettingsCard(title: "Map", symbol: "map") {
            SegmentedChoice(title: "Style", symbol: "paintpalette", selection: $settings.data.display.mapStyle,
                            options: MapStyleChoice.allCases.map { ($0.rawValue, $0) })
            SegmentedChoice(title: "Map strength", symbol: "circle.lefthalf.filled", selection: $settings.data.display.mapOpacity,
                            options: [("Off", 0.0), ("Faint", 0.4), ("Normal", 0.7), ("Bright", 1.0)])
            SettingsToggle("Airports", symbol: "airplane.departure", isOn: $settings.data.display.showAirports)
            SettingsToggle("Trails", symbol: "point.topleft.down.to.point.bottomright.curvepath", isOn: $settings.data.display.showTrails,
                           detail: "A fading line behind each aircraft showing where it has just been.")
        }
    }

    // MARK: aircraft

    private var aircraftCard: some View {
        SettingsCard(title: "Aircraft", symbol: "airplane") {
            SegmentedChoice(title: "Labels", symbol: "textformat", selection: $settings.data.display.labels,
                            options: LabelMode.allCases.map { ($0.rawValue, $0) })
            SegmentedChoice(title: "Units", symbol: "ruler", selection: $settings.data.display.units,
                            options: [("ft · kt · nm", Units.aviation), ("m · km/h · km", Units.metric)])
            SegmentedChoice(title: "Hide below", symbol: "arrow.down.to.line", selection: $settings.data.filter.minAltitudeFt,
                            options: [("Nothing", 0.0), ("1,000 ft", 1_000), ("5,000", 5_000), ("10,000", 10_000), ("20,000", 20_000)])
            SegmentedChoice(title: "Hide above", symbol: "arrow.up.to.line", selection: $settings.data.filter.maxAltitudeFt,
                            options: [("Nothing", 60_000.0), ("30,000 ft", 30_000), ("20,000", 20_000), ("10,000", 10_000)])
            SettingsToggle("Show aircraft on the ground", symbol: "road.lanes", isOn: $settings.data.filter.includeGround)
            SettingsToggle("Only cross-checked aircraft", symbol: "checkmark.shield", isOn: $settings.data.filter.onlyCrossChecked,
                           detail: "Hides anything only one feed can see.")
        }
    }

    // MARK: data feeds

    private func feedDescription(_ id: SourceID) -> String {
        switch id {
        case .adsbLol: return "Community ADS-B network. Updates about every 10 seconds."
        case .adsbFi: return "Community ADS-B network. Updates every 5 seconds."
        case .openSky: return model.openSkyAccount == .anonymous ? "Research network. Updates every 4 minutes without an account." : "Research network. Updates every 30 seconds."
        }
    }

    private var feedsCard: some View {
        SettingsCard(title: "Data feeds", symbol: "antenna.radiowaves.left.and.right") {
            ForEach(SourceID.allCases, id: \.self) { id in
                SettingsToggle(id.rawValue, symbol: store.status[id]?.isLive(at: Date()) == true ? "checkmark.circle" : "circle",
                               isOn: Binding(get: { model.isSourceEnabled(id) }, set: { model.setSource(id, enabled: $0) }),
                               detail: feedDescription(id))
            }
            Text("Aircraft are cross-checked between feeds, so more feeds means better confidence. Turn one off if you want to see what a single feed shows.").settingsFootnote()
            Divider().overlay(Color.white.opacity(0.12))
            openSkyAccount
        }
    }

    @ViewBuilder private var openSkyAccount: some View {
        Label("OpenSky account (optional)", systemImage: "person.crop.circle")
            .font(.system(.body, design: .rounded, weight: .medium))
            .foregroundStyle(Theme.primary)
        switch model.openSkyAccount {
        case .signedIn(let id):
            Label("Signed in as \(id)", systemImage: "checkmark.circle").foregroundStyle(Theme.green)
            Button("Remove OpenSky account", role: .destructive) { model.removeOpenSky() }
        default:
            TextField("Client ID", text: $openSkyID)
            SecureField("Client secret", text: $openSkySecret)
            Button(model.openSkyAccount == .checking ? "Checking…" : "Check and save") {
                let id = openSkyID, secret = openSkySecret
                Task {
                    await model.saveOpenSky(clientID: id, clientSecret: secret)
                    if case .signedIn = model.openSkyAccount { openSkyID = ""; openSkySecret = "" }
                }
            }
            .disabled(model.openSkyAccount == .checking || openSkyID.isEmpty || openSkySecret.isEmpty)
            if model.openSkyAccount == .failed {
                Text("OpenSky didn't accept that client ID and secret.").foregroundStyle(Theme.red)
            }
            Text("Create an API client in your OpenSky account to cross-check more often (every 30 s instead of every 4 min). Stored in this device's keychain only.").settingsFootnote()
        }
    }

    // MARK: alerts

    private func watching(_ rule: WatchRule) -> Binding<Bool> {
        Binding {
            settings.data.watchRules.contains(rule)
        } set: { on in
            if on { if !settings.data.watchRules.contains(rule) { settings.data.watchRules.append(rule) } }
            else { settings.data.watchRules.removeAll { $0 == rule } }
        }
    }

    private var alertsCard: some View {
        SettingsCard(title: "Watch for", symbol: "binoculars") {
            Text("Shows a banner when one of these flies into range.").settingsFootnote()
            ForEach(WatchRule.suggestions) { rule in
                SettingsToggle(rule.label, symbol: rule.kind == .airline ? "building.2" : "airplane", isOn: watching(rule))
            }
            ForEach(settings.data.watchRules.filter { r in !WatchRule.suggestions.contains(r) }) { rule in
                SettingsToggle("\(rule.kind.rawValue.capitalized) \(rule.value)", symbol: "star", isOn: watching(rule))
            }
            Picker("Add a rule for", selection: $customWatchKind) {
                ForEach(WatchRule.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Code (ACA, A388, C-GITS)", text: $customWatch).onSubmit(addCustomWatch)
        }
    }

    private func addCustomWatch() {
        let v = customWatch.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        let rule = WatchRule(kind: customWatchKind, value: v)
        if !settings.data.watchRules.contains(rule) { settings.data.watchRules.append(rule) }
        customWatch = ""
    }

    // MARK: saved places

    private var savedPlacesCard: some View {
        SettingsCard(title: "Saved places", symbol: "bookmark") {
            if settings.data.savedPlaces.isEmpty {
                Text("Nothing saved yet. Use Save this view above, or the bookmark in Search, to keep a spot you want to come back to.").settingsFootnote()
            }
            ForEach(settings.data.savedPlaces) { place in
                HStack {
                    Button { model.go(to: place); onDone() } label: {
                        Label(place.name, systemImage: "mappin.and.ellipse")
                            .font(.system(.body, design: .rounded, weight: .medium))
                    }
                    Spacer()
                    Button(role: .destructive) { model.deleteSavedPlace(place.id) } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Remove \(place.name)")
                }
            }
            if !settings.data.recents.isEmpty {
                Button("Clear recent searches") { model.clearRecents() }
            }
        }
    }

    // MARK: device and about

    #if os(iOS)
    private var deviceCard: some View {
        SettingsCard(title: "Device", symbol: "iphone") {
            SettingsToggle("Keep screen awake", symbol: "sun.max", isOn: $settings.data.display.keepAwake,
                           detail: "Stops the screen sleeping while Live Airspace is open, handy on a dock or stand.")
            if model.locationDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Label("Allow location in Settings", systemImage: "gear") }
            }
        }
    }
    #endif

    private var aboutCard: some View {
        SettingsCard(title: "About", symbol: "info.circle") {
            Text("Live Airspace cross-checks three independent public ADS-B feeds (adsb.lol, adsb.fi and the OpenSky Network) and shows what they agree on. Aircraft details and photos come from adsbdb.com, airports from OurAirports, and the map from Apple Maps.").settingsFootnote()
            Label("Your location is only used to choose the area shown. There are no accounts, ads or tracking.", systemImage: "lock")
                .font(.system(.footnote, design: .rounded)).foregroundStyle(Theme.secondary)
            Label("Free community data with no guarantee. Not for navigation or safety-critical use.", systemImage: "exclamationmark.triangle")
                .font(.system(.footnote, design: .rounded)).foregroundStyle(Theme.amber)
            if let onShowWelcome {
                Button { onShowWelcome() } label: { Label("Show welcome screen", systemImage: "sparkles") }
            }
            #if !os(tvOS)
            if let url = URL(string: "https://github.com/LoganMHawkins/live-airspace") {
                Link(destination: url) { Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
            #endif
            Button("Reset all settings", role: .destructive) { confirmReset = true }
                .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset", role: .destructive) { model.resetSettings() }
                    Button("Cancel", role: .cancel) {}
                }
            Text(version).settingsFootnote()
        }
    }
}
