import Foundation

/// Cross-references reports from independent feeds into one list of aircraft.
public struct AirspaceMerger: Sendable {
    /// Reports older than this are ignored.
    public var maxAge: TimeInterval = 60
    /// Position gap (after dead-reckoning every report to the same instant) above which sources are "disputed".
    public var positionToleranceNM: Double = 2.0
    /// Barometric altitude gap above which altitude is flagged as disputed.
    public var altitudeToleranceFt: Double = 500
    /// Plausibility limits; anything outside is a bad decode and is dropped.
    public var maxGroundSpeedKt: Double = 1_000
    public var maxAltitudeFt: Double = 65_000

    public init() {}

    /// - Parameter reliability: 0...1 track record per source (default 1). Breaks ties when two sources disagree.
    public func merge(_ reports: [SourceReport], now: Date, reliability: [SourceID: Double] = [:]) -> [Aircraft] {
        let valid = reports.filter { isPlausible($0, now: now) }
        return Dictionary(grouping: valid, by: \.icao24).values
            .map { combine($0, now: now, reliability: reliability) }
            .sorted { $0.id < $1.id }
    }

    func isPlausible(_ r: SourceReport, now: Date) -> Bool {
        guard (-90...90).contains(r.latitude), (-180...180).contains(r.longitude),
              !(r.latitude == 0 && r.longitude == 0) else { return false }
        let age = now.timeIntervalSince(r.positionTime)
        guard age <= maxAge, age >= -5 else { return false }
        if let gs = r.groundSpeedKt, gs < 0 || gs > maxGroundSpeedKt { return false }
        if let alt = r.altitudeFt, alt > maxAltitudeFt || alt < -2_000 { return false }
        return true
    }

    func combine(_ reports: [SourceReport], now: Date, reliability: [SourceID: Double] = [:]) -> Aircraft {
        // Freshest fix first.
        let ordered = reports.sorted { $0.positionTime > $1.positionTime }
        let positions = ordered.map { extrapolated($0, to: now) }

        func maxGap(_ idx: [Int]) -> Double {
            var gap = 0.0
            for i in idx { for j in idx where j > i { gap = max(gap, Geo.distanceNM(positions[i], positions[j])) } }
            return gap
        }

        // With three or more sources, a single dissenter can be identified and set aside.
        var active = Array(ordered.indices)
        var outlier: SourceID?
        if active.count >= 3, maxGap(active) > positionToleranceNM {
            // The dissenter is far from everyone else. Compare total distance to the others: the max alone is symmetric
            // (the dissenter and each agreeing source are equally far from each other).
            func total(_ i: Int) -> Double { active.reduce(0) { $0 + Geo.distanceNM(positions[i], positions[$1]) } }
            let worst = active.max { total($0) < total($1) }!
            let rest = active.filter { $0 != worst }
            if maxGap(rest) <= positionToleranceNM {
                outlier = ordered[worst].source
                active = rest
            }
        }

        let spread = maxGap(active)
        let agreement: Agreement
        if ordered.count < 2 {
            agreement = .single
        } else if spread > positionToleranceNM {
            agreement = .disputed(spreadNM: spread)
        } else {
            agreement = .confirmed(spreadNM: spread)
        }

        let used = active.map { ordered[$0] }
        // Agreeing sources: freshest fix leads. Disputed: trust the source with the better track record first.
        let lead = agreement.isDisputed
            ? used.max { (reliability[$0.source] ?? 1, $0.positionTime) < (reliability[$1.source] ?? 1, $1.positionTime) }!
            : used[0]

        let altitudes = used.compactMap(\.altitudeFt)
        let altitudeDisputed = altitudes.count > 1
            && (altitudes.max()! - altitudes.min()!) > altitudeToleranceFt
        let altitude = altitudes.isEmpty ? nil : median(altitudes, leadValue: lead.altitudeFt)

        // Identity comes from whichever source has it, readsb feeds first (they carry type/registration).
        let identity = ordered.sorted { ($0.source == .openSky ? 1 : 0) < ($1.source == .openSky ? 1 : 0) }
        let onGroundVotes = used.filter(\.onGround).count

        return Aircraft(
            id: lead.icao24,
            callsign: identity.lazy.compactMap(\.callsign).first,
            registration: identity.lazy.compactMap(\.registration).first,
            typeCode: identity.lazy.compactMap(\.typeCode).first,
            latitude: lead.latitude, longitude: lead.longitude,
            altitudeFt: altitude,
            groundSpeedKt: ([lead] + used).lazy.compactMap(\.groundSpeedKt).first,
            trackDeg: ([lead] + used).lazy.compactMap(\.trackDeg).first,
            verticalRateFpm: ([lead] + used).lazy.compactMap(\.verticalRateFpm).first,
            onGround: onGroundVotes * 2 > used.count,
            squawk: used.lazy.compactMap(\.squawk).first,
            positionTime: lead.positionTime,
            sources: Array(Set(ordered.map(\.source))).sorted(),
            agreement: agreement,
            altitudeDisputed: altitudeDisputed,
            outlierSource: outlier
        )
    }

    private func extrapolated(_ r: SourceReport, to date: Date) -> Coordinate {
        let here = Coordinate(latitude: r.latitude, longitude: r.longitude)
        guard !r.onGround, let gs = r.groundSpeedKt, let track = r.trackDeg else { return here }
        let dt = min(max(date.timeIntervalSince(r.positionTime), 0), maxAge)
        return Geo.project(here, trackDeg: track, distanceNM: gs * dt / 3600)
    }

    /// Median; with an even count, prefer the freshest source's value over averaging two disagreeing ones.
    private func median(_ values: [Double], leadValue: Double?) -> Double? {
        if values.count % 2 == 0 { return leadValue ?? values[0] }
        return values.sorted()[values.count / 2]
    }
}
