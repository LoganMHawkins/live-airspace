import Foundation

public struct SourceStatus: Sendable, Equatable {
    public var lastSuccess: Date?
    public var lastError: String?
    public var aircraftCount = 0
    /// Source is backing off (rate limit or repeated failure) until this time.
    public var pausedUntil: Date?
    /// How often this source is meant to answer; used to judge whether it has gone quiet.
    public var expectedInterval: TimeInterval = 5

    /// Answered recently enough to be trusted (three missed polls, at least 45 s).
    public func isLive(at now: Date) -> Bool {
        guard let last = lastSuccess else { return false }
        return now.timeIntervalSince(last) < max(expectedInterval * 3, 45)
    }
}

public enum FeedHealth: Sendable, Equatable {
    case live
    /// Some sources are down; the rest are still reporting.
    case degraded(down: [SourceID])
    /// Nothing has answered recently, so what's on screen is stale or empty.
    case down
}

/// Polls every source on its own schedule and publishes the cross-referenced result.
@MainActor
public final class AirspaceStore: ObservableObject {
    @Published public private(set) var aircraft: [Aircraft] = []
    @Published public private(set) var status: [SourceID: SourceStatus] = [:]
    /// Recent dead-reckoned positions per aircraft, oldest first, for drawing trails.
    @Published public private(set) var feedHealth: FeedHealth = .live
    /// 0...1 track record per source: how often it agreed with the others instead of being the odd one out.
    @Published public private(set) var reliability: [SourceID: Double] = [:]
    /// Registration, type, operator, photo and route for aircraft near the centre and the selected one.
    @Published public private(set) var details: [String: AircraftDetails] = [:]
    /// The aircraft the info card is showing; nil means "whichever is nearest".
    @Published public private(set) var selectedID: String?
    /// Sources currently switched on (the user can turn feeds off in Settings).
    @Published public private(set) var enabledSources: [SourceID] = SourceID.allCases
    /// Which aircraft are shown; changing it re-filters immediately.
    public var filter = AircraftFilter() {
        didSet { if filter != oldValue { refreshMerge() } }
    }
    /// Rules to watch for; set by the app.
    public var watchRules: [WatchRule] = []
    /// A watch rule that just matched; clears itself after a while.
    @Published public private(set) var activeAlert: WatchAlert?
    /// When each aircraft first appeared, for fade-in.
    public private(set) var firstSeen: [String: Date] = [:]
    private var alerted: Set<String> = []
    @Published public private(set) var trails: [String: [Coordinate]] = [:]
    @Published public var config: AirspaceConfig {
        didSet {
            guard config != oldValue else { return }
            if config.center != oldValue.center {
                // A short hop (panning, following a plane) keeps what's on screen while the feeds refetch; a jump clears it.
                let hop = Geo.distanceNM(config.center, oldValue.center)
                restart(keepData: hop <= 2 * max(config.radiusNM, oldValue.radiusNM))
            } else if config.radiusNM != oldValue.radiusNM {
                restart(keepData: true)  // same place, new range: keep what's on screen while the feeds refetch
            }
            // A renamed airspace (for example "Near you" becoming "Near Toronto") needs no refetch.
        }
    }

    public private(set) var sources: [any AirspaceSource]
    private let enrichment: EnrichmentService?
    private var requestedDetails: Set<String> = []
    private var selectionSetAt = Date.distantPast
    private var selectionGraceUntil = Date.distantPast
    private var selectionPinned = false
    private var disabled: Set<SourceID> = []
    /// Aircraft found by a search that the feeds haven't reported yet, shown until the real data arrives.
    private var injected: [String: (aircraft: Aircraft, added: Date)] = [:]
    private var merger = AirspaceMerger()
    private var latest: [SourceID: [SourceReport]] = [:]
    private var tasks: [Task<Void, Never>] = []
    private let maxTrailPoints = 40

    public init(
        config: AirspaceConfig = .default,
        sources: [any AirspaceSource] = AirspaceStore.defaultSources(),
        enrichment: EnrichmentService? = EnrichmentService()
    ) {
        self.config = config
        self.sources = sources
        self.enrichment = enrichment
    }

    /// adsb.lol, adsb.fi and OpenSky (signed in when the user has saved an OpenSky API client).
    nonisolated public static func defaultSources(openSky credentials: OpenSkyCredentials? = OpenSkyCredentialStore.load()) -> [any AirspaceSource] {
        [ReadsbSource.adsbLol, ReadsbSource.adsbFi, OpenSkySource(credentials: credentials)]
    }

    public func start() {
        guard tasks.isEmpty else { return }
        for source in sources {
            tasks.append(Task { [weak self] in await self?.poll(source) })
        }
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refreshMerge()
            }
        })
    }

    /// Swaps the OpenSky source (for example after the user saves or removes credentials) and restarts polling.
    public func setOpenSkyCredentials(_ credentials: OpenSkyCredentials?) {
        let wasRunning = !tasks.isEmpty
        stop()
        sources = sources.map { $0.id == .openSky ? OpenSkySource(credentials: credentials) : $0 }
        status[.openSky] = nil
        latest[.openSky] = nil
        if wasRunning { start() }
    }

    /// Turns one feed on or off without touching the others.
    public func setSourceEnabled(_ id: SourceID, _ enabled: Bool) {
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        enabledSources = SourceID.allCases.filter { !disabled.contains($0) }
        if !enabled {
            latest[id] = nil
            status[id] = nil
        }
        refreshMerge()
    }

    /// Shows an aircraft found by search straight away, before the feeds around its new location have answered.
    public func inject(_ aircraft: Aircraft) {
        injected[aircraft.id] = (aircraft, Date())
        refreshMerge()
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func restart(keepData: Bool) {
        let wasRunning = !tasks.isEmpty
        stop()
        if !keepData {
            latest.removeAll()
            trails.removeAll()
            requestedDetails.removeAll()
            // A pinned selection (following an aircraft, or a search result) must survive jumping to where it is.
            if !selectionPinned { selectedID = nil }
            alerted.removeAll()
            firstSeen.removeAll()
            activeAlert = nil
            aircraft = []
            refreshMerge()  // shows any search-injected aircraft straight away
        }
        if wasRunning { start() }
    }

    private func poll(_ source: any AirspaceSource) async {
        var failures = 0
        while !Task.isCancelled {
            if disabled.contains(source.id) {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            var wait = source.minimumInterval
            let center = config.center, radius = config.radiusNM
            do {
                let reports = try await source.fetch(center: center, radiusNM: radius, now: Date())
                failures = 0
                latest[source.id] = reports
                status[source.id] = SourceStatus(lastSuccess: Date(), aircraftCount: reports.count, expectedInterval: source.minimumInterval)
                refreshMerge()
            } catch {
                failures += 1
                var s = status[source.id] ?? SourceStatus(expectedInterval: source.minimumInterval)
                s.lastError = Self.describe(error)
                if case SourceError.rateLimited(let retry) = error {
                    wait = min(max(retry ?? 0, wait * 2), 3_600)
                } else {
                    wait = min(source.minimumInterval * pow(2, Double(failures)), 300)
                }
                s.pausedUntil = Date().addingTimeInterval(wait)
                status[source.id] = s
                // A failing source's old reports age out via the merger's maxAge, so no manual purge here.
            }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func refreshMerge() {
        let now = Date()
        var merged = merger.merge(latest.filter { !disabled.contains($0.key) }.values.flatMap { $0 }, now: now, reliability: reliability)
        let present = Set(merged.map(\.id))
        injected = injected.filter { !present.contains($0.key) && now.timeIntervalSince($0.value.added) < 90 }
        merged += injected.values.map(\.aircraft)
        aircraft = merged.filter(filter.allows)
        updateReliability()
        updateFeedHealth(now: now)
        updateFocus(now: now)
        updateAlerts(now: now)
        var next: [String: [Coordinate]] = [:]
        for ac in aircraft where !ac.onGround {
            var points = trails[ac.id] ?? []
            let p = ac.position(at: now)
            if let last = points.last, Geo.distanceNM(last, p) < 0.15 {
                // too close to add a new point
            } else {
                points.append(p)
            }
            if points.count > maxTrailPoints { points.removeFirst(points.count - maxTrailPoints) }
            next[ac.id] = points
        }
        trails = next
    }

    private func updateAlerts(now: Date) {
        for ac in aircraft where firstSeen[ac.id] == nil { firstSeen[ac.id] = now }
        firstSeen = firstSeen.filter { id, _ in aircraft.contains { $0.id == id } }
        if let a = activeAlert, now.timeIntervalSince(a.since) > 20 { activeAlert = nil }
        guard activeAlert == nil else { return }
        for ac in aircraft where !ac.onGround {
            guard let rule = watchRules.first(where: { $0.matches(ac) }) else { continue }
            let key = "\(ac.id)|\(rule.id)"
            guard alerted.insert(key).inserted else { continue }
            activeAlert = WatchAlert(id: key, rule: rule, aircraftName: ac.displayName, typeCode: ac.typeCode, since: now)
            break
        }
    }

    // MARK: selection and details

    /// Airborne aircraft, nearest to the centre first.
    public func aircraftByDistance(from center: Coordinate? = nil, at now: Date = Date()) -> [Aircraft] {
        let origin = center ?? config.center
        return aircraft.filter { !$0.onGround }
            .sorted { Geo.distanceNM(origin, $0.position(at: now)) < Geo.distanceNM(origin, $1.position(at: now)) }
    }

    /// The aircraft the info card shows: the selected one, else the nearest.
    public var focus: Aircraft? {
        if let selectedID, let ac = aircraft.first(where: { $0.id == selectedID }) { return ac }
        return aircraftByDistance().first
    }

    /// Selects a specific aircraft (a tap, search result or Top Shelf tile).
    /// - Parameters:
    ///   - pin: keep it selected indefinitely (used while the camera follows it) instead of reverting to "nearest" after a while.
    ///   - grace: how long to wait for the feeds to report it before giving up if it isn't in range yet.
    public func select(_ id: String, pin: Bool = false, grace: TimeInterval = 20) {
        selectedID = id
        selectionSetAt = Date()
        selectionGraceUntil = Date().addingTimeInterval(grace)
        selectionPinned = pin
    }

    /// Back to showing the nearest aircraft.
    public func clearSelection() {
        selectedID = nil
        selectionPinned = false
    }

    /// Moves the selection through the aircraft by distance (+1 farther, -1 nearer), wrapping around.
    public func cycleSelection(_ step: Int) {
        let list = aircraftByDistance()
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == focus?.id } ?? 0
        selectedID = list[((current + step) % list.count + list.count) % list.count].id
        selectionSetAt = Date()
        selectionGraceUntil = .distantPast
        selectionPinned = false
        updateFocus(now: Date())
    }

    private func updateFocus(now: Date) {
        // Selection reverts to "nearest" after a while, or if the aircraft leaves.
        if let id = selectedID {
            let expired = !selectionPinned && now.timeIntervalSince(selectionSetAt) > 90
            let gone = now > selectionGraceUntil && !aircraft.contains(where: { $0.id == id })
            if expired || gone {
                selectedID = nil
                selectionPinned = false
            }
        }
        guard let enrichment else { return }
        var wanted = Array(aircraftByDistance(at: now).prefix(6))
        if let f = focus, !wanted.contains(where: { $0.id == f.id }) { wanted.append(f) }
        for ac in wanted {
            let key = "\(ac.id)|\(ac.callsign ?? "")"
            guard requestedDetails.insert(key).inserted else { continue }
            let id = ac.id, callsign = ac.callsign
            Task { [weak self] in
                let d = await enrichment.details(hex: id, callsign: callsign)
                guard let self, !d.isEmpty else { return }
                self.details[id] = d
            }
        }
    }

    /// Slowly learns which sources tend to be the odd one out. Only cases where blame is clear (3+ sources) count.
    private func updateReliability() {
        var next = reliability
        for ac in aircraft where ac.sources.count >= 3 {
            for id in ac.sources {
                let hit = ac.outlierSource == id ? 0.0 : 1.0
                next[id] = (next[id] ?? 1) * 0.998 + hit * 0.002
            }
        }
        if next != reliability { reliability = next }
    }

    private func updateFeedHealth(now: Date) {
        let active = sources.map(\.id).filter { !disabled.contains($0) }
        let down = active.filter { !(status[$0]?.isLive(at: now) ?? false) }
        let health: FeedHealth = down.isEmpty ? .live : (down.count == active.count ? .down : .degraded(down: down))
        if health != feedHealth { feedHealth = health }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case SourceError.badStatus(let code): return "HTTP \(code)"
        case SourceError.rateLimited: return "Rate limited"
        case SourceError.malformed: return "Unreadable response"
        case SourceError.authFailed: return "Sign-in failed"
        default: return (error as NSError).localizedDescription
        }
    }
}
