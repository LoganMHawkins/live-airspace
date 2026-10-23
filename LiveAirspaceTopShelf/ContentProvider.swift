import TVServices
import LiveAirspaceKit

/// Shows aircraft currently overhead (with photos) on the Apple TV Home Screen while the app is in the top row.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task { completionHandler(await Self.build()) }
    }

    private static func build() async -> TVTopShelfContent? {
        let config = SharedConfig.load() ?? .default

        // One quick look at a single feed; the Top Shelf only needs a rough "what's overhead".
        let now = Date()
        guard let reports = try? await ReadsbSource.adsbFi.fetch(center: config.center, radiusNM: min(config.radiusNM, 60), now: now) else { return nil }
        let nearest = AirspaceMerger().merge(reports, now: now)
            .filter { !$0.onGround }
            .sorted { Geo.distanceNM(config.center, $0.position(at: now)) < Geo.distanceNM(config.center, $1.position(at: now)) }
            .prefix(8)

        let enrichment = EnrichmentService()
        var items: [TVTopShelfSectionedItem] = []
        for ac in nearest {
            let d = await enrichment.details(hex: ac.id, callsign: ac.callsign)
            guard let photo = d.photoURL else { continue }  // no photo, no tile
            let item = TVTopShelfSectionedItem(identifier: ac.id)
            var title = ac.displayName
            if let o = d.origin, let dest = d.destination { title += "  \(o.code) → \(dest.code)" }
            else if let type = d.typeName ?? ac.typeCode { title += "  \(type)" }
            item.title = title
            item.imageShape = .hdtv
            item.setImageURL(photo, for: [.screenScale1x, .screenScale2x])
            item.displayAction = TVTopShelfAction(url: URL(string: "liveairspace://aircraft/\(ac.id)")!)
            items.append(item)
            if items.count == 5 { break }
        }
        guard !items.isEmpty else { return nil }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Overhead now · \(config.name)"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
