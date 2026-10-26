import Foundation

/// One row in the search results.
public enum SearchResult: Identifiable, Equatable, Sendable {
    /// An aircraft, either already on screen or found by a worldwide lookup.
    case aircraft(Aircraft, onScreen: Bool)
    case airport(Airport)
    /// A city, address or landmark from the system geocoder.
    case place(name: String, subtitle: String?, coordinate: Coordinate)
    case saved(SavedPlace)

    public var id: String {
        switch self {
        case .aircraft(let ac, _): return "ac:\(ac.id)"
        case .airport(let ap): return "ap:\(ap.icao)"
        case .place(let name, _, let c): return "pl:\(name):\(c.latitude),\(c.longitude)"
        case .saved(let p): return "sv:\(p.id.uuidString)"
        }
    }
}

/// Matching and ranking for search. Pure functions over the airport table and the aircraft on screen.
public enum SearchEngine {
    /// Lower-cased with accents and punctuation removed, so "Montréal" matches "montreal" and "C-GITS" matches "cgits".
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
            .trimmingCharacters(in: .whitespaces)
    }

    /// Airports by code or name, best match first.
    public static func airports(matching query: String, limit: Int = 8) -> [Airport] {
        let q = normalize(query)
        guard q.count >= 2 else { return [] }
        let tokens = q.split(separator: " ").map(String.init)
        var scored: [(Airport, Int)] = []
        for ap in AirportDatabase.all {
            let code = normalize(ap.code), icao = normalize(ap.icao), name = normalize(ap.name)
            var score = 0
            if code == q || icao == q { score = 100 }
            else if code.hasPrefix(q) || icao.hasPrefix(q) { score = 80 }
            else if name.hasPrefix(q) { score = 65 }
            else if tokens.allSatisfy({ name.contains($0) }) { score = 45 }
            if score > 0 { scored.append((ap, score + (ap.isLarge ? 5 : 0))) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }.prefix(limit).map(\.0)
    }

    public static func nearbyAirports(to center: Coordinate, limit: Int = 5) -> [Airport] {
        AirportDatabase.all.sorted { Geo.distanceNM(center, $0.coordinate) < Geo.distanceNM(center, $1.coordinate) }.prefix(limit).map { $0 }
    }

    /// Aircraft already on screen: by callsign, registration, type, hex, airline, flight number, or an airport it is flying to/from.
    public static func aircraft(matching query: String, in list: [Aircraft], details: [String: AircraftDetails], limit: Int = 12) -> [Aircraft] {
        let q = normalize(query)
        guard q.count >= 2 else { return [] }
        var scored: [(Aircraft, Int)] = []
        for ac in list {
            let d = details[ac.id]
            var best = 0
            func consider(_ field: String?, exact: Int, prefix: Int, contains: Int = 0) {
                guard let f = field.map(normalize), !f.isEmpty else { return }
                if f == q { best = max(best, exact) } else if f.hasPrefix(q) { best = max(best, prefix) } else if contains > 0, f.contains(q) { best = max(best, contains) }
            }
            consider(ac.callsign, exact: 100, prefix: 90)
            consider(ac.registration ?? d?.registration, exact: 100, prefix: 88)
            consider(ac.id, exact: 95, prefix: 70)
            consider(ac.typeCode, exact: 85, prefix: 60)
            consider(d?.flightNumber, exact: 95, prefix: 85)
            consider(d?.airline, exact: 70, prefix: 60, contains: 50)
            consider(d?.operatorName, exact: 60, prefix: 50, contains: 40)
            consider(d?.typeName, exact: 60, prefix: 50, contains: 45)
            consider(d?.origin?.code, exact: 75, prefix: 0)
            consider(d?.destination?.code, exact: 75, prefix: 0)
            consider(d?.origin?.city, exact: 55, prefix: 45)
            consider(d?.destination?.city, exact: 55, prefix: 45)
            if best > 0 { scored.append((ac, best)) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.displayName < $1.0.displayName }.prefix(limit).map(\.0)
    }
}

/// Worldwide lookup of a single flight, registration, hex or aircraft type through the feeds' search endpoints.
/// These only ever report what is flying right now.
public actor FeedLookup {
    public struct Outcome: Sendable {
        public var aircraft: [Aircraft]
        public var rateLimited: Bool
    }

    private var cache: [String: (when: Date, outcome: Outcome)] = [:]
    private let ttl: TimeInterval = 20

    public init() {}

    public func lookup(_ raw: String, now: Date = Date()) async -> Outcome {
        let q = raw.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: " ", with: "")
        guard q.count >= 3, q.count <= 12, q.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return Outcome(aircraft: [], rateLimited: false) }
        if let hit = cache[q], now.timeIntervalSince(hit.when) < ttl { return hit.outcome }

        var urls: [(URL, SourceID)] = []
        func add(_ s: String, _ id: SourceID) { if let u = URL(string: s) { urls.append((u, id)) } }
        let fi = "https://opendata.adsb.fi/api/v2"
        if q.count == 6, q.allSatisfy(\.isHexDigit) { add("\(fi)/hex/\(q.lowercased())", .adsbFi) }
        if !q.contains("-"), q.count <= 8 { add("\(fi)/callsign/\(q)", .adsbFi) }
        if Self.looksLikeRegistration(q) { add("\(fi)/registration/\(q)", .adsbFi) }

        var reports: [SourceReport] = []
        var limited = false
        for (url, id) in urls {
            do { reports += try ReadsbSource.parse(try await HTTP.get(url), source: id, now: now) }
            catch SourceError.rateLimited { limited = true }
            catch { continue }
        }
        // Type codes (A388, B748…) fall back to adsb.lol's type endpoint, which lists every one flying.
        if reports.isEmpty, !q.contains("-"), (3...4).contains(q.count), q.first?.isLetter == true,
           let url = URL(string: "https://api.adsb.lol/v2/type/\(q)") {
            do { reports += try ReadsbSource.parse(try await HTTP.get(url), source: .adsbLol, now: now) }
            catch SourceError.rateLimited { limited = true }
            catch { }
        }

        var merger = AirspaceMerger()
        merger.maxAge = 120
        let found = merger.merge(reports, now: now).sorted { ($0.altitudeFt ?? 0) > ($1.altitudeFt ?? 0) }
        let outcome = Outcome(aircraft: Array(found.prefix(40)), rateLimited: limited && found.isEmpty)
        if !outcome.rateLimited { cache[q] = (now, outcome) }
        return outcome
    }

    /// Letters and digits, with a dash (C-GITS, G-EUYM) or the US N-number shape.
    static func looksLikeRegistration(_ q: String) -> Bool {
        if q.contains("-") { return q.count >= 4 }
        return q.first == "N" && q.count >= 4 && q.count <= 6 && q.dropFirst().first?.isNumber == true
    }
}
