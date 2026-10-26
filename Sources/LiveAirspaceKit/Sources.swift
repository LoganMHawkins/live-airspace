import Foundation

public enum SourceError: Error, Equatable {
    case badStatus(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case malformed
    case authFailed
}

public protocol AirspaceSource: Sendable {
    var id: SourceID { get }
    /// Shortest polite gap between requests to this source.
    var minimumInterval: TimeInterval { get }
    func fetch(center: Coordinate, radiusNM: Double, now: Date) async throws -> [SourceReport]
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "LiveAirspace/1.0 (personal ambient display)"]
        return URLSession(configuration: config)
    }()

    static func get(_ url: URL, bearer: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SourceError.malformed }
        switch http.statusCode {
        case 200: return data
        case 401 where bearer != nil, 403 where bearer != nil: throw SourceError.authFailed
        case 429:
            let retry = http.value(forHTTPHeaderField: "X-Rate-Limit-Retry-After-Seconds")
                ?? http.value(forHTTPHeaderField: "Retry-After")
            throw SourceError.rateLimited(retryAfter: retry.flatMap(TimeInterval.init))
        default: throw SourceError.badStatus(http.statusCode)
        }
    }
}

// MARK: - readsb-format feeds (adsb.lol, adsb.fi)

public struct ReadsbSource: AirspaceSource {
    public let id: SourceID
    public let minimumInterval: TimeInterval
    private let makeURL: @Sendable (Coordinate, Double) -> URL?

    public init(id: SourceID, minimumInterval: TimeInterval, makeURL: @escaping @Sendable (Coordinate, Double) -> URL?) {
        self.id = id
        self.minimumInterval = minimumInterval
        self.makeURL = makeURL
    }

    /// adsb.lol allows about 10 requests a minute, so it polls more slowly than adsb.fi.
    public static let adsbLol = ReadsbSource(id: .adsbLol, minimumInterval: 10) { c, r in
        URL(string: "https://api.adsb.lol/v2/point/\(c.latitude)/\(c.longitude)/\(Int(min(r, 250).rounded(.up)))")
    }

    public static let adsbFi = ReadsbSource(id: .adsbFi, minimumInterval: 5) { c, r in
        URL(string: "https://opendata.adsb.fi/api/v2/lat/\(c.latitude)/lon/\(c.longitude)/dist/\(Int(min(r, 250).rounded(.up)))")
    }

    public func fetch(center: Coordinate, radiusNM: Double, now: Date) async throws -> [SourceReport] {
        guard let url = makeURL(center, radiusNM) else { throw SourceError.malformed }
        return try Self.parse(try await HTTP.get(url), source: id, now: now)
    }

    public static func parse(_ data: Data, source: SourceID, now: Date) throws -> [SourceReport] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = (root["ac"] ?? root["aircraft"]) as? [[String: Any]]
        else { throw SourceError.malformed }

        return list.compactMap { ac in
            guard let hex = ac["hex"] as? String, !hex.hasPrefix("~"),  // ~ = non-ICAO address, can't be matched across feeds
                  let lat = number(ac["lat"]), let lon = number(ac["lon"])
            else { return nil }

            let onGround: Bool
            var altitude: Double?
            if let s = ac["alt_baro"] as? String {
                onGround = s == "ground"
                altitude = onGround ? 0 : nil
            } else {
                onGround = false
                altitude = number(ac["alt_baro"])
            }
            let seenPos = number(ac["seen_pos"]) ?? number(ac["seen"]) ?? 0
            return SourceReport(
                icao24: hex, source: source,
                callsign: clean(ac["flight"] as? String),
                registration: clean(ac["r"] as? String),
                typeCode: clean(ac["t"] as? String),
                latitude: lat, longitude: lon, altitudeFt: altitude,
                groundSpeedKt: number(ac["gs"]), trackDeg: number(ac["track"]),
                verticalRateFpm: number(ac["baro_rate"]) ?? number(ac["geom_rate"]),
                onGround: onGround, squawk: clean(ac["squawk"] as? String),
                category: clean(ac["category"] as? String),
                positionTime: now.addingTimeInterval(-seenPos)
            )
        }
    }
}

// MARK: - OpenSky Network

/// An OpenSky API client (create one in your OpenSky account). Entered by the user in Settings and kept in the keychain.
public struct OpenSkyCredentials: Sendable, Equatable {
    public var clientID: String
    public var clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

/// Fetches and caches OAuth2 client-credentials tokens for OpenSky.
actor OpenSkyTokenProvider {
    private let credentials: OpenSkyCredentials
    private var token: String?
    private var expires = Date.distantPast

    init(credentials: OpenSkyCredentials) { self.credentials = credentials }

    func bearer() async throws -> String {
        if let token, expires.timeIntervalSinceNow > 60 { return token }
        var request = URLRequest(url: URL(string: "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "client_credentials"),
            .init(name: "client_id", value: credentials.clientID),
            .init(name: "client_secret", value: credentials.clientSecret),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { throw SourceError.authFailed }
        token = access
        expires = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 1_800)
        return access
    }
}

extension OpenSkyCredentials {
    /// True if OpenSky accepts these credentials (fetches a token).
    public func verify() async -> Bool {
        (try? await OpenSkyTokenProvider(credentials: self).bearer()) != nil
    }
}

public struct OpenSkySource: AirspaceSource {
    public let id = SourceID.openSky
    /// Anonymous access allows ~400 requests/day (so ~4 min between polls); a registered account allows ~4,000 (~30 s).
    public let minimumInterval: TimeInterval
    let tokens: OpenSkyTokenProvider?

    public init(credentials: OpenSkyCredentials? = nil, minimumInterval: TimeInterval? = nil) {
        self.tokens = credentials.map(OpenSkyTokenProvider.init)
        self.minimumInterval = minimumInterval ?? (credentials == nil ? 240 : 30)
    }

    public var isAuthenticated: Bool { tokens != nil }

    public func fetch(center: Coordinate, radiusNM: Double, now: Date) async throws -> [SourceReport] {
        let dLat = radiusNM / 60
        let dLon = radiusNM / (60 * max(cos(center.latitude * .pi / 180), 0.05))
        var comps = URLComponents(string: "https://opensky-network.org/api/states/all")!
        comps.queryItems = [
            .init(name: "lamin", value: String(center.latitude - dLat)),
            .init(name: "lamax", value: String(center.latitude + dLat)),
            .init(name: "lomin", value: String(center.longitude - dLon)),
            .init(name: "lomax", value: String(center.longitude + dLon)),
        ]
        guard let url = comps.url else { throw SourceError.malformed }
        let bearer = try await tokens?.bearer()
        let reports = try Self.parse(try await HTTP.get(url, bearer: bearer), now: now)
        // The API returns a bounding box; trim to the circle so sources cover the same area.
        return reports.filter {
            Geo.distanceNM(center, Coordinate(latitude: $0.latitude, longitude: $0.longitude)) <= radiusNM
        }
    }

    public static func parse(_ data: Data, now: Date) throws -> [SourceReport] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SourceError.malformed }
        guard let states = root["states"] as? [[Any]] else { return [] }  // null when no aircraft

        return states.compactMap { s in
            guard s.count > 14, let hex = s[0] as? String,
                  let lon = number(s[5]), let lat = number(s[6])
            else { return nil }
            let fixTime = number(s[3]).map { Date(timeIntervalSince1970: $0) } ?? now
            return SourceReport(
                icao24: hex, source: .openSky,
                callsign: clean(s[1] as? String),
                latitude: lat, longitude: lon,
                altitudeFt: number(s[7]).map { $0 * 3.28084 },
                groundSpeedKt: number(s[9]).map { $0 * 1.943844 },
                trackDeg: number(s[10]),
                verticalRateFpm: number(s[11]).map { $0 * 196.8504 },
                onGround: (s[8] as? Bool) ?? false,
                squawk: clean(s[14] as? String),
                positionTime: fixTime
            )
        }
    }
}

// MARK: - helpers

private func number(_ any: Any?) -> Double? {
    if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
    return nil
}

private func clean(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
    return t
}
