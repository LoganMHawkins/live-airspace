import SwiftUI
import CoreLocation
import LiveAirspaceKit

/// Drives the search screen: instant local matches, then (after a short pause) a worldwide flight lookup and the system geocoder.
@MainActor
final class SearchModel: ObservableObject {
    struct Section: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var rows: [SearchResult]
    }

    @Published var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    @Published private(set) var sections: [Section] = []
    @Published private(set) var busy = false
    @Published private(set) var note: String?

    let model: LiveAirspaceModel
    private let lookup = FeedLookup()
    private var remote: Task<Void, Never>?
    private var remoteAircraft: [Aircraft] = []
    private var places: [SearchResult] = []

    init(model: LiveAirspaceModel) {
        self.model = model
        rebuild()
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private func queryChanged() {
        remote?.cancel()
        remoteAircraft = []
        places = []
        note = nil
        busy = false
        rebuild()
        let q = trimmed
        guard q.count >= 3 else { return }
        busy = true
        remote = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, let self else { return }
            async let found = self.lookup.lookup(q)
            async let geo = Self.geocode(q)
            let (outcome, placeResults) = await (found, geo)
            guard !Task.isCancelled else { return }
            self.remoteAircraft = outcome.aircraft
            self.places = placeResults
            let looksLikeFlight = q.contains { $0.isNumber }
            self.note = outcome.rateLimited && (looksLikeFlight || SearchEngine.airports(matching: q, limit: 1).isEmpty)
                ? "Flight lookup is busy. Try again in a moment." : nil
            self.busy = false
            self.rebuild()
        }
    }

    /// Cities, addresses and landmarks from the system geocoder.
    private static func geocode(_ query: String) async -> [SearchResult] {
        guard let marks = try? await CLGeocoder().geocodeAddressString(query) else { return [] }
        return marks.prefix(4).compactMap { mark in
            guard let loc = mark.location, let name = mark.name ?? mark.locality else { return nil }
            let subtitle = [mark.locality, mark.administrativeArea, mark.country].compactMap { $0 }.filter { $0 != name }.joined(separator: ", ")
            return .place(name: name, subtitle: subtitle.isEmpty ? nil : subtitle,
                          coordinate: Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
        }
    }

    func rebuild() {
        let store = model.store
        let data = model.settings.data
        var out: [Section] = []
        let q = trimmed
        if q.isEmpty {
            if !data.savedPlaces.isEmpty { out.append(Section(id: "saved", title: "Saved places", symbol: "bookmark", rows: data.savedPlaces.map { .saved($0) })) }
            if !data.recents.isEmpty { out.append(Section(id: "recent", title: "Recent", symbol: "clock", rows: data.recents.map { .saved($0) })) }
            out.append(Section(id: "nearby", title: "Airports nearby", symbol: "airplane.departure",
                               rows: SearchEngine.nearbyAirports(to: store.config.center, limit: 5).map { .airport($0) }))
            out.append(Section(id: "popular", title: "Busy skies", symbol: "flame",
                               rows: AirspaceConfig.presets.map { .place(name: $0.name, subtitle: nil, coordinate: $0.center) }))
        } else {
            let onScreen = SearchEngine.aircraft(matching: q, in: store.aircraft, details: store.details)
            let onScreenIDs = Set(store.aircraft.map(\.id))
            var rows: [SearchResult] = onScreen.map { .aircraft($0, onScreen: true) }
            for ac in remoteAircraft where !rows.contains(where: { if case .aircraft(let a, _) = $0 { return a.id == ac.id } else { return false } }) {
                rows.append(.aircraft(ac, onScreen: onScreenIDs.contains(ac.id)))
            }
            if !rows.isEmpty { out.append(Section(id: "aircraft", title: "Aircraft", symbol: "airplane", rows: rows)) }
            let airports = SearchEngine.airports(matching: q)
            if !airports.isEmpty { out.append(Section(id: "airports", title: "Airports", symbol: "airplane.departure", rows: airports.map { .airport($0) })) }
            if !places.isEmpty { out.append(Section(id: "places", title: "Places", symbol: "mappin.and.ellipse", rows: places)) }
            let nq = SearchEngine.normalize(q)
            let mine = (data.savedPlaces + data.recents).filter { SearchEngine.normalize($0.name).contains(nq) }
            if !mine.isEmpty { out.append(Section(id: "mine", title: "Saved and recent", symbol: "bookmark", rows: mine.map { .saved($0) })) }
        }
        sections = out
    }

    /// Opens a result: aircraft are followed, places and airports are flown to.
    func choose(_ result: SearchResult) {
        switch result {
        case .aircraft(let ac, _):
            model.showAircraft(ac)
        case .airport(let ap):
            let name = "\(ap.code) Airport"
            model.goTo(ap.coordinate, name: name, radiusNM: 25)
            model.addRecent(name: name, coordinate: ap.coordinate, radiusNM: 25)
        case .place(let name, _, let c):
            model.goTo(c, name: name, radiusNM: 40)
            model.addRecent(name: name, coordinate: c)
        case .saved(let place):
            model.go(to: place)
            model.addRecent(name: place.name, coordinate: place.coordinate, radiusNM: place.radiusNM)
        }
    }

    func bookmark(_ result: SearchResult) {
        switch result {
        case .airport(let ap): model.settings.data.savedPlaces.append(SavedPlace(name: "\(ap.code) Airport", latitude: ap.coordinate.latitude, longitude: ap.coordinate.longitude, radiusNM: 25))
        case .place(let name, _, let c): model.settings.data.savedPlaces.append(SavedPlace(name: name, latitude: c.latitude, longitude: c.longitude))
        default: break
        }
        rebuild()
    }

    func isSaved(_ result: SearchResult) -> Bool {
        let saved = model.settings.data.savedPlaces
        switch result {
        case .airport(let ap): return saved.contains { $0.name == "\(ap.code) Airport" }
        case .place(let name, _, _): return saved.contains { $0.name == name }
        default: return false
        }
    }

    func delete(_ place: SavedPlace) {
        model.deleteSavedPlace(place.id)
        model.settings.data.recents.removeAll { $0.id == place.id }
        rebuild()
    }

    /// The first row, for pressing Return.
    var firstResult: SearchResult? { sections.first?.rows.first }
}

/// Search for a flight, airport or place; pick a result to fly the radar there.
public struct SearchView: View {
    @StateObject private var search: SearchModel
    @ObservedObject private var model: LiveAirspaceModel
    @ObservedObject private var store: AirspaceStore
    var onClose: () -> Void
    @FocusState private var focused: Bool

    public init(model: LiveAirspaceModel, onClose: @escaping () -> Void) {
        self.model = model
        self.store = model.store
        self.onClose = onClose
        _search = StateObject(wrappedValue: SearchModel(model: model))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField("Flight, airport, place or registration", text: $search.query)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { if let first = search.firstResult { choose(first) } }
                    if search.busy { ProgressView().controlSize(.small) }
                    if !search.query.isEmpty {
                        Button { search.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassCard(cornerRadius: 16)
                Button("Cancel", action: onClose)
            }
            .padding(16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let note = search.note { Label(note, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.amber) }
                    ForEach(search.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(section.title, systemImage: section.symbol)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.ink.opacity(0.8))
                            VStack(spacing: 6) {
                                ForEach(section.rows) { row in resultRow(row) }
                            }
                        }
                    }
                    if search.sections.isEmpty && !search.busy {
                        Text("No matches yet. Try a callsign like ACA1040, a registration like C-FIVQ, an airport code like LHR, or a city.")
                            .settingsFootnote()
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
        .onChange(of: store.aircraft.count) { _, _ in search.rebuild() }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 520, idealHeight: 620)
        .onExitCommand(perform: onClose)
        #endif
    }

    private func choose(_ result: SearchResult) {
        search.choose(result)
        onClose()
    }

    private func distanceText(_ c: Coordinate) -> String {
        model.settings.data.display.units.distance(Geo.distanceNM(store.config.center, c))
    }

    @ViewBuilder private func resultRow(_ result: SearchResult) -> some View {
        HStack(spacing: 10) {
            Button { choose(result) } label: {
                HStack(spacing: 14) {
                    Image(systemName: symbol(result))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint(result))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(tint(result).opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(result)).font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(Theme.primary).lineLimit(2)
                        if let sub = subtitle(result) { Text(sub).font(.system(.footnote, design: .rounded)).foregroundStyle(Theme.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 8)
                    if let trailing = trailing(result) { Text(trailing).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.secondary) }
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.secondary.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if !os(tvOS)
            if case .saved(let place) = result {
                Button { search.delete(place) } label: { Image(systemName: "trash").foregroundStyle(Theme.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Remove \(place.name)")
            } else if isBookmarkable(result) {
                Button { search.bookmark(result) } label: {
                    Image(systemName: search.isSaved(result) ? "bookmark.fill" : "bookmark").foregroundStyle(Theme.cyan)
                }
                .buttonStyle(.plain).accessibilityLabel("Save place")
            }
            #endif
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassCard(cornerRadius: 16)
    }

    private func isBookmarkable(_ r: SearchResult) -> Bool {
        switch r { case .airport, .place: return true; default: return false }
    }

    private func symbol(_ r: SearchResult) -> String {
        switch r {
        case .aircraft(let ac, _): return ac.isRotorcraft ? "helicopter" : "airplane"
        case .airport: return "airplane.departure"
        case .place: return "mappin.and.ellipse"
        case .saved: return "bookmark"
        }
    }

    private func tint(_ r: SearchResult) -> Color {
        switch r {
        case .aircraft(let ac, _): return altitudeColor(ac.altitudeFt)
        case .airport: return Theme.violet
        case .place: return Theme.green
        case .saved: return Theme.cyan
        }
    }

    private func title(_ r: SearchResult) -> String {
        switch r {
        case .aircraft(let ac, _): return ac.displayName
        case .airport(let ap): return ap.name
        case .place(let name, _, _): return name
        case .saved(let p): return p.name
        }
    }

    private func subtitle(_ r: SearchResult) -> String? {
        let units = model.settings.data.display.units
        switch r {
        case .aircraft(let ac, let onScreen):
            let d = store.details[ac.id]
            var parts: [String] = []
            if let o = d?.origin, let dest = d?.destination { parts.append("\(o.code) → \(dest.code)") }
            if let airline = d?.airline ?? d?.operatorName { parts.append(airline) }
            if let t = d?.typeName ?? ac.typeCode { parts.append(t) }
            if let alt = ac.altitudeFt { parts.append(units.altitude(alt)) }
            if !onScreen { parts.append("live now") }
            return parts.joined(separator: " · ")
        case .airport(let ap): return "\(ap.code) · \(ap.icao)"
        case .place(_, let sub, _): return sub
        case .saved: return nil
        }
    }

    private func trailing(_ r: SearchResult) -> String? {
        switch r {
        case .aircraft(let ac, let onScreen): return onScreen ? distanceText(ac.position(at: Date())) : nil
        case .airport(let ap): return distanceText(ap.coordinate)
        case .place(_, _, let c): return distanceText(c)
        case .saved(let p): return distanceText(p.coordinate)
        }
    }
}
