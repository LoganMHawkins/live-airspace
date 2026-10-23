import SwiftUI
import LiveAirspaceKit

/// Settings for both the Apple TV app (full-screen sheet) and the Mac screen saver (configure sheet).
public struct SettingsView: View {
    @ObservedObject var model: LiveAirspaceModel
    @ObservedObject var settings: AppSettings
    var allowsNearMe: Bool
    var onDone: () -> Void

    @State private var customWatch = ""
    @State private var customWatchKind = WatchRule.Kind.airline
    @State private var openSkyID = ""
    @State private var openSkySecret = ""
    @State private var latText = ""
    @State private var lonText = ""

    public init(model: LiveAirspaceModel, allowsNearMe: Bool = true, onDone: @escaping () -> Void) {
        self.model = model
        self.settings = model.settings
        self.allowsNearMe = allowsNearMe
        self.onDone = onDone
    }

    private var placeChoice: Binding<String> {
        Binding {
            switch settings.data.place {
            case .nearMe: return "nearMe"
            case .preset(let n): return "preset:\(n)"
            case .custom: return "custom"
            }
        } set: { v in
            if v == "nearMe" { settings.data.place = .nearMe }
            else if v == "custom" {
                let c = Double(latText).flatMap { lat in Double(lonText).map { (lat, $0) } } ?? (45.3225, -75.6692)
                settings.data.place = .custom(name: "Custom", latitude: c.0, longitude: c.1)
            } else { settings.data.place = .preset(String(v.dropFirst("preset:".count))) }
        }
    }

    private var mapStrength: Binding<Double> {
        Binding { settings.data.display.mapOpacity } set: { settings.data.display.mapOpacity = $0 }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    Picker("Centre on", selection: placeChoice) {
                        if allowsNearMe { Text("Near me").tag("nearMe") }
                        ForEach(AirspaceConfig.presets, id: \.name) { Text($0.name).tag("preset:\($0.name)") }
                        Text("Custom coordinates").tag("custom")
                    }
                    if case .custom = settings.data.place {
                        TextField("Latitude (e.g. 45.32)", text: $latText).onSubmit(applyCustom)
                        TextField("Longitude (e.g. -75.67)", text: $lonText).onSubmit(applyCustom)
                    }
                    Picker("Range", selection: $settings.data.radiusNM) {
                        ForEach([10.0, 20, 30, 40, 60, 80, 100, 150], id: \.self) { Text(settings.data.display.units.distance($0).replacingOccurrences(of: ".0", with: "")).tag($0) }
                    }
                }

                Section("Map") {
                    Picker("Map strength", selection: mapStrength) {
                        Text("Off").tag(0.0)
                        Text("Faint").tag(0.4)
                        Text("Normal").tag(0.7)
                        Text("Bright").tag(1.0)
                    }
                    Toggle("Light map", isOn: $settings.data.display.lightMap)
                    Toggle("Airports", isOn: $settings.data.display.showAirports)
                    Toggle("Trails", isOn: $settings.data.display.showTrails)
                }

                Section("Labels and units") {
                    Picker("Aircraft labels", selection: $settings.data.display.labels) {
                        ForEach(LabelMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Units", selection: $settings.data.display.units) {
                        ForEach(Units.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section {
                    switch model.openSkyAccount {
                    case .signedIn(let id):
                        Label("Signed in as \(id)", systemImage: "checkmark.circle")
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
                            Text("OpenSky didn't accept that client ID and secret.").foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("OpenSky account (optional)")
                } footer: {
                    Text("Create an API client in your OpenSky account to cross-check more often (every 30 s instead of every 4 min). Stored in this device's keychain only.")
                }

                Section("Watch for (shows a banner when one arrives)") {
                    ForEach(WatchRule.suggestions) { rule in
                        Toggle(rule.label, isOn: watching(rule))
                    }
                    ForEach(settings.data.watchRules.filter { r in !WatchRule.suggestions.contains(r) }) { rule in
                        Toggle("\(rule.kind.rawValue.capitalized) \(rule.value)", isOn: watching(rule))
                    }
                    Picker("Add a rule for", selection: $customWatchKind) {
                        ForEach(WatchRule.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    TextField("Code (ACA, A388, C-GITS)", text: $customWatch).onSubmit(addCustomWatch)
                }

                Section {
                    Button("Done", action: onDone)
                }
            }
            .navigationTitle("Live Airspace")
        }
        .onAppear {
            if case .custom(_, let lat, let lon) = settings.data.place { latText = String(lat); lonText = String(lon) }
        }
    }

    private func watching(_ rule: WatchRule) -> Binding<Bool> {
        Binding {
            settings.data.watchRules.contains(rule)
        } set: { on in
            if on { if !settings.data.watchRules.contains(rule) { settings.data.watchRules.append(rule) } }
            else { settings.data.watchRules.removeAll { $0 == rule } }
        }
    }

    private func addCustomWatch() {
        let v = customWatch.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        let rule = WatchRule(kind: customWatchKind, value: v)
        if !settings.data.watchRules.contains(rule) { settings.data.watchRules.append(rule) }
        customWatch = ""
    }

    private func applyCustom() {
        guard let lat = Double(latText), let lon = Double(lonText), (-90...90).contains(lat), (-180...180).contains(lon) else { return }
        settings.data.place = .custom(name: "Custom", latitude: lat, longitude: lon)
    }
}
