import SwiftUI
import MapKit
import LiveAirspaceKit

/// Full-screen radar-style live traffic display. Shared by the tvOS app and the macOS screen saver.
public struct LiveAirspaceView: View {
    @ObservedObject var model: LiveAirspaceModel
    @ObservedObject var store: AirspaceStore
    @ObservedObject var settings: AppSettings
    var ambient: Bool

    /// - Parameter ambient: slowly drifts the HUD and map and dims static elements to protect OLED/plasma panels.
    public init(model: LiveAirspaceModel, ambient: Bool = true) {
        self.model = model
        self.store = model.store
        self.settings = model.settings
        self.ambient = ambient
    }

    public var body: some View {
        let display = settings.data.display
        let focus = store.focus
        GeometryReader { geo in
            let scale = max(geo.size.height / 1080, 0.5)
            ZStack {
                if display.mapOpacity > 0 {
                    MapLayer(config: store.config, size: geo.size, ambient: ambient, opacity: display.mapOpacity, light: display.lightMap)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    Canvas { context, size in
                        Renderer(
                            context: context, size: size, now: timeline.date,
                            aircraft: store.aircraft, trails: store.trails, firstSeen: store.firstSeen,
                            status: store.status, reliability: store.reliability, feedHealth: store.feedHealth,
                            details: store.details, focusID: focus?.id,
                            airports: display.showAirports ? AirportDatabase.near(store.config.center, radiusNM: store.config.radiusNM * 1.15) : [],
                            config: store.config, display: display, ambient: ambient
                        ).draw()
                    }
                }
                // Cards ride the same slow drift as the radar.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    ZStack {
                        if let alert = store.activeAlert {
                            AlertBanner(alert: alert, scale: scale)
                                .padding(.top, 150 * scale)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if let focus {
                            InfoCard(aircraft: focus, details: store.details[focus.id], config: store.config,
                                     units: display.units, scale: scale, now: timeline.date)
                                .padding(56 * scale)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: store.activeAlert)
                    .offset(ambient ? ambientDrift(at: timeline.date, scale: scale) : .zero)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(red: 0.01, green: 0.02, blue: 0.03))
        .ignoresSafeArea()
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }
}

// MARK: - shared bits

/// Slow figure-eight drift, a few points either way, so no pixel stays lit forever.
func ambientDrift(at date: Date, scale: CGFloat) -> CGSize {
    let t = date.timeIntervalSinceReferenceDate
    return CGSize(width: sin(t / 41) * 18 * scale, height: cos(t / 53) * 14 * scale)
}

let ink = Color(red: 0.55, green: 0.95, blue: 0.85)

func altitudeColor(_ ft: Double?) -> Color {
    switch ft ?? 0 {
    case ..<5_000: return Color(red: 1.0, green: 0.78, blue: 0.35)
    case ..<18_000: return Color(red: 0.45, green: 0.95, blue: 0.7)
    case ..<30_000: return Color(red: 0.4, green: 0.8, blue: 1.0)
    default: return Color(red: 0.75, green: 0.6, blue: 1.0)
    }
}

let disputedColor = Color(red: 1.0, green: 0.45, blue: 0.4)

// MARK: - map

/// Muted street map (dark by default) aligned to the radar's projection: radar centre = airspace centre, same nm-per-point scale.
private struct MapLayer: View {
    var config: AirspaceConfig
    var size: CGSize
    var ambient: Bool
    var opacity: Double
    var light: Bool

    var body: some View {
        let scale = max(size.height / 1080, 0.5)
        // Oversized so the drift never exposes an edge.
        let pad = 80 * scale
        let mapSize = CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
        let pxPerNM = min(size.width, size.height) / 2 * 0.86 / config.radiusNM
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: config.center.latitude, longitude: config.center.longitude),
            latitudinalMeters: mapSize.height / pxPerNM * 1852,
            longitudinalMeters: mapSize.width / pxPerNM * 1852)

        // The map is drawn larger than the screen (so drift never shows an edge) but sits in an overlay and is clipped,
        // otherwise its oversize frame would stretch the whole stack and push the radar and cards off-screen.
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            // In ambient mode the map slowly breathes between full and ~55% strength so no tile stays at one brightness.
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breathe = ambient ? 0.775 + 0.225 * sin(t / 95) : 1
            Color.clear
                .overlay(
                    Map(position: .constant(.region(region)), interactionModes: [])
                        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                        .environment(\.colorScheme, light ? .light : .dark)
                        .frame(width: mapSize.width, height: mapSize.height)
                        .opacity(opacity * breathe)
                        .offset(ambient ? ambientDrift(at: timeline.date, scale: scale) : .zero)
                )
                .frame(width: size.width, height: size.height)
                .clipped()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - cards

private struct AlertBanner: View {
    var alert: WatchAlert
    var scale: CGFloat

    var body: some View {
        HStack(spacing: 18 * scale) {
            Image(systemName: "binoculars.fill").font(.system(size: 34 * scale))
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text("WATCH: \(alert.rule.label.uppercased())").font(.system(size: 22 * scale, weight: .bold, design: .monospaced))
                Text("\(alert.aircraftName)\(alert.typeCode.map { " · \($0)" } ?? "") is in range")
                    .font(.system(size: 26 * scale, design: .monospaced))
            }
        }
        .foregroundColor(.black)
        .padding(.horizontal, 32 * scale).padding(.vertical, 18 * scale)
        .background(Capsule().fill(Color(red: 1.0, green: 0.85, blue: 0.4)))
    }
}

private struct InfoCard: View {
    var aircraft: Aircraft
    var details: AircraftDetails?
    var config: AirspaceConfig
    var units: Units
    var scale: CGFloat
    var now: Date

    var body: some View {
        let color = aircraft.agreement.isDisputed ? disputedColor : altitudeColor(aircraft.altitudeFt)
        let distance = Geo.distanceNM(config.center, aircraft.position(at: now))
        VStack(alignment: .leading, spacing: 10 * scale) {
            if let url = details?.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 520 * scale, height: 230 * scale)
                            .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                            .opacity(0.9)
                    case .empty:
                        RoundedRectangle(cornerRadius: 14 * scale).fill(Color.white.opacity(0.05))
                            .frame(width: 520 * scale, height: 230 * scale)
                    default:
                        EmptyView()  // photo missing or failed to load: show the card without it
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 14 * scale) {
                Text(aircraft.displayName).font(.system(size: 40 * scale, weight: .bold, design: .monospaced)).foregroundColor(color)
                if let fn = details?.flightNumber, fn != aircraft.callsign {
                    Text(fn).font(.system(size: 26 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.6))
                }
            }
            if let airline = details?.airline ?? details?.operatorName {
                Text(airline).font(.system(size: 26 * scale, weight: .medium)).foregroundColor(.white.opacity(0.85))
            }
            if let o = details?.origin, let d = details?.destination {
                HStack(spacing: 12 * scale) {
                    Text(o.code).font(.system(size: 34 * scale, weight: .bold, design: .monospaced))
                    Image(systemName: "arrow.right").font(.system(size: 24 * scale))
                    Text(d.code).font(.system(size: 34 * scale, weight: .bold, design: .monospaced))
                }.foregroundColor(.white)
                Text("\(o.city ?? o.name) to \(d.city ?? d.name)").font(.system(size: 20 * scale)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
            }
            let typeLine = [details?.typeName ?? aircraft.typeCode, details?.registration ?? aircraft.registration].compactMap { $0 }.joined(separator: " · ")
            if !typeLine.isEmpty {
                Text(typeLine).font(.system(size: 22 * scale, design: .monospaced)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
            }
            Text(stats(distance: distance)).font(.system(size: 22 * scale, design: .monospaced)).foregroundColor(color.opacity(0.9))
            Text(crossCheck).font(.system(size: 18 * scale, design: .monospaced))
                .foregroundColor(aircraft.agreement.isDisputed ? disputedColor : ink.opacity(0.55))
        }
        .padding(24 * scale)
        .frame(width: 568 * scale, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22 * scale).fill(Color.black.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 22 * scale).stroke(color.opacity(0.35), lineWidth: 1.5 * scale))
    }

    private func stats(distance: Double) -> String {
        var parts: [String] = []
        if let alt = aircraft.altitudeFt { parts.append(units.altitude(alt) + (aircraft.altitudeDisputed ? "?" : "")) }
        if let gs = aircraft.groundSpeedKt { parts.append(units.speed(gs)) }
        if let vr = aircraft.verticalRateFpm, abs(vr) > 300 { parts.append((vr > 0 ? "↑ " : "↓ ") + units.rate(vr)) }
        parts.append(units.distance(distance))
        return parts.joined(separator: " · ")
    }

    private var crossCheck: String {
        let names = aircraft.sources.map(\.rawValue).joined(separator: ", ")
        switch aircraft.agreement {
        case .single: return "1 source: \(names)"
        case .confirmed(let gap):
            var s = "\(aircraft.confirmingSources) sources agree (\(String(format: "%.1f", gap)) nm)"
            if let o = aircraft.outlierSource { s += " · \(o.rawValue) off" }
            return s
        case .disputed(let gap): return "Sources disagree by \(String(format: "%.1f", gap)) nm"
        }
    }
}

// MARK: - radar canvas

private struct Renderer {
    var context: GraphicsContext
    var size: CGSize
    var now: Date
    var aircraft: [Aircraft]
    var trails: [String: [Coordinate]]
    var firstSeen: [String: Date]
    var status: [SourceID: SourceStatus]
    var reliability: [SourceID: Double]
    var feedHealth: FeedHealth
    var details: [String: AircraftDetails]
    var focusID: String?
    var airports: [Airport]
    var config: AirspaceConfig
    var display: DisplaySettings
    var ambient: Bool

    private var scale: CGFloat { max(size.height / 1080, 0.5) }
    private var drift: CGSize { ambient ? ambientDrift(at: now, scale: scale) : .zero }

    private struct Placed {
        var ac: Aircraft
        var point: CGPoint
        var focus: Bool
        var labelRect: CGRect?
        var line1: GraphicsContext.ResolvedText?
        var line2: GraphicsContext.ResolvedText?
    }

    func draw() {
        var ctx = context
        ctx.translateBy(x: drift.width, y: drift.height)

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radiusPx = min(size.width, size.height) / 2 * 0.86
        let pxPerNM = radiusPx / config.radiusNM

        func point(_ c: Coordinate) -> CGPoint {
            let o = Geo.offsetNM(from: config.center, to: c)
            return CGPoint(x: center.x + o.east * pxPerNM, y: center.y - o.north * pxPerNM)
        }

        let visible = aircraft.filter { !$0.onGround }
        var placed = layout(visible, point: point, ctx: ctx)

        drawGrid(&ctx, center: center, radiusPx: radiusPx)

        // Airports sit under the traffic; their labels only appear where aircraft labels left room.
        var taken = placed.compactMap(\.labelRect) + placed.map { CGRect(x: $0.point.x - 30 * scale, y: $0.point.y - 30 * scale, width: 60 * scale, height: 60 * scale) }
        drawAirports(&ctx, point: point, taken: &taken)

        if let focus = placed.first(where: \.focus) {
            drawRoute(&ctx, focus.ac, from: focus.point, center: center, radiusPx: radiusPx, point: point)
        }
        if display.showTrails { for p in placed { drawTrail(&ctx, p.ac, point: point) } }
        placed.sort { ($0.ac.altitudeFt ?? 0) < ($1.ac.altitudeFt ?? 0) }
        for p in placed { drawAircraft(&ctx, p) }

        drawHUD(&ctx, visible: visible)
        drawLegend(&ctx)
    }

    // MARK: label layout

    private func labelStrings(_ ac: Aircraft) -> (String, String) {
        let u = display.units
        var detail: [String] = []
        if let t = ac.typeCode { detail.append(t) }
        if let alt = ac.altitudeFt {
            var a = u.altitude(alt) + (ac.altitudeDisputed ? "?" : "")
            if let vr = ac.verticalRateFpm { if vr > 500 { a += "↑" } else if vr < -500 { a += "↓" } }
            detail.append(a)
        }
        if let gs = ac.groundSpeedKt { detail.append(u.speed(gs)) }
        return (ac.displayName, detail.joined(separator: " · "))
    }

    /// Places labels greedily, nearest aircraft first, trying right/left/above/below and skipping any that would overlap.
    private func layout(_ visible: [Aircraft], point: (Coordinate) -> CGPoint, ctx: GraphicsContext) -> [Placed] {
        let byDistance = visible.sorted { Geo.distanceNM(config.center, $0.position(at: now)) < Geo.distanceNM(config.center, $1.position(at: now)) }
        let s = 20 * scale
        var result: [Placed] = byDistance.map {
            Placed(ac: $0, point: point($0.position(at: now)), focus: $0.id == focusID)
        }
        // Reserve every aircraft icon so labels never cover a neighbour.
        var rects = result.map { CGRect(x: $0.point.x - s * 1.2, y: $0.point.y - s * 1.2, width: s * 2.4, height: s * 2.4) }
        // Keep labels clear of the info card in the bottom-right corner (card is 568 wide and about 600 tall with a photo).
        rects.append(CGRect(x: size.width - 56 * scale - 568 * scale, y: size.height - 56 * scale - 620 * scale, width: 568 * scale, height: 620 * scale))
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 20 * scale, dy: 20 * scale)

        let order = result.indices.sorted { a, b in
            if result[a].focus != result[b].focus { return result[a].focus }
            return a < b
        }
        for (rank, i) in order.enumerated() {
            let isFocus = result[i].focus
            switch display.labels {
            case .off where !isFocus: continue
            case .nearest where !isFocus && rank >= 5: continue
            default: break
            }
            let (l1, l2) = labelStrings(result[i].ac)
            let color = result[i].ac.agreement.isDisputed ? disputedColor : altitudeColor(result[i].ac.altitudeFt)
            let t1 = ctx.resolve(Text(l1).font(.system(size: 22 * scale, weight: .semibold, design: .monospaced)).foregroundColor(color))
            let t2 = ctx.resolve(Text(l2).font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(color.opacity(0.7)))
            let m1 = t1.measure(in: CGSize(width: 800, height: 100)), m2 = t2.measure(in: CGSize(width: 800, height: 100))
            let w = max(m1.width, m2.width), h = m1.height + (l2.isEmpty ? 0 : m2.height)
            let p = result[i].point, gap = s * 1.4
            let candidates = [
                CGRect(x: p.x + gap, y: p.y - h / 2, width: w, height: h),
                CGRect(x: p.x - gap - w, y: p.y - h / 2, width: w, height: h),
                CGRect(x: p.x - w / 2, y: p.y - gap - h, width: w, height: h),
                CGRect(x: p.x - w / 2, y: p.y + gap, width: w, height: h),
            ]
            let fit = candidates.first { r in bounds.contains(r) && !rects.contains { $0.intersects(r.insetBy(dx: -6 * scale, dy: -3 * scale)) } }
            if let r = fit ?? (isFocus ? candidates[0] : nil) {
                result[i].labelRect = r
                result[i].line1 = t1
                result[i].line2 = l2.isEmpty ? nil : t2
                rects.append(r)
            }
        }
        return result
    }

    // MARK: grid

    private func drawGrid(_ ctx: inout GraphicsContext, center: CGPoint, radiusPx: CGFloat) {
        let dim: Double = ambient ? 0.5 : 0.8
        let line = ink.opacity(0.16 * dim)
        for i in 1...3 {
            let r = radiusPx * CGFloat(i) / 3
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(line), lineWidth: 1.5 * scale)
            let nm = config.radiusNM * Double(i) / 3
            let label = Text(display.units.distance(nm).replacingOccurrences(of: ".0", with: ""))
                .font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.4 * dim))
            ctx.draw(label, at: CGPoint(x: center.x + r * 0.707 + 6 * scale, y: center.y - r * 0.707 - 4 * scale), anchor: .leading)
        }
        var cross = Path()
        cross.move(to: CGPoint(x: center.x - radiusPx, y: center.y)); cross.addLine(to: CGPoint(x: center.x + radiusPx, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y - radiusPx)); cross.addLine(to: CGPoint(x: center.x, y: center.y + radiusPx))
        ctx.stroke(cross, with: .color(line), style: StrokeStyle(lineWidth: 1 * scale, dash: [4 * scale, 8 * scale]))
        for (name, dx, dy) in [("N", 0.0, -1.0), ("E", 1.0, 0.0), ("S", 0.0, 1.0), ("W", -1.0, 0.0)] {
            ctx.draw(Text(name).font(.system(size: 22 * scale, weight: .semibold, design: .monospaced)).foregroundColor(ink.opacity(0.45 * dim)),
                     at: CGPoint(x: center.x + dx * (radiusPx + 26 * scale), y: center.y + dy * (radiusPx + 26 * scale)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 5 * scale, y: center.y - 5 * scale, width: 10 * scale, height: 10 * scale)),
                 with: .color(ink.opacity(0.7)))
    }

    // MARK: airports and route

    private func drawAirports(_ ctx: inout GraphicsContext, point: (Coordinate) -> CGPoint, taken: inout [CGRect]) {
        let dim: Double = ambient ? 0.7 : 1
        for ap in airports {
            let p = point(ap.coordinate)
            let r = (ap.isLarge ? 9 : 6) * scale
            var d = Path()
            d.move(to: CGPoint(x: p.x, y: p.y - r)); d.addLine(to: CGPoint(x: p.x + r, y: p.y))
            d.addLine(to: CGPoint(x: p.x, y: p.y + r)); d.addLine(to: CGPoint(x: p.x - r, y: p.y)); d.closeSubpath()
            ctx.stroke(d, with: .color(.white.opacity((ap.isLarge ? 0.6 : 0.4) * dim)), lineWidth: 1.8 * scale)
            // Skip the label if an aircraft label or icon is in the way.
            let text = ctx.resolve(Text(ap.code).font(.system(size: (ap.isLarge ? 19 : 16) * scale, design: .monospaced)).foregroundColor(.white.opacity((ap.isLarge ? 0.6 : 0.4) * dim)))
            let m = text.measure(in: CGSize(width: 200, height: 50))
            let rect = CGRect(x: p.x + r + 5 * scale, y: p.y - m.height / 2, width: m.width, height: m.height)
            if !taken.contains(where: { $0.intersects(rect.insetBy(dx: -4 * scale, dy: -2 * scale)) }) {
                ctx.draw(text, at: rect.origin, anchor: .topLeading)
                taken.append(rect)
            }
        }
    }

    /// Dashed line from the selected aircraft toward its destination (bright) and back toward its origin (faint),
    /// with the airport code where each leaves the radar.
    private func drawRoute(_ ctx: inout GraphicsContext, _ ac: Aircraft, from p: CGPoint, center: CGPoint, radiusPx: CGFloat, point: (Coordinate) -> CGPoint) {
        guard let d = details[ac.id] else { return }
        let color = altitudeColor(ac.altitudeFt)
        var clipped = ctx
        clipped.clip(to: Path(ellipseIn: CGRect(x: center.x - radiusPx, y: center.y - radiusPx, width: 2 * radiusPx, height: 2 * radiusPx)))
        for (ref, bright) in [(d.destination, true), (d.origin, false)] {
            guard let ref else { continue }
            let target = point(ref.coordinate)
            var path = Path()
            path.move(to: p); path.addLine(to: target)
            clipped.stroke(path, with: .color(color.opacity(bright ? 0.55 : 0.22)),
                           style: StrokeStyle(lineWidth: 2 * scale, dash: [10 * scale, 8 * scale]))
            // Where the line leaves the radar circle: solve |p + t·v - center| = radius.
            let v = CGPoint(x: target.x - p.x, y: target.y - p.y)
            let f = CGPoint(x: p.x - center.x, y: p.y - center.y)
            let a = v.x * v.x + v.y * v.y
            guard a > 1 else { continue }
            let b = 2 * (f.x * v.x + f.y * v.y), c = f.x * f.x + f.y * f.y - radiusPx * radiusPx
            let disc = b * b - 4 * a * c
            guard disc >= 0 else { continue }
            let t = (-b + sqrt(disc)) / (2 * a)
            guard t > 0, t < 1 else { continue }  // airport is inside the radar; its own marker covers it
            let edge = CGPoint(x: p.x + v.x * t, y: p.y + v.y * t)
            ctx.draw(Text(ref.code).font(.system(size: 22 * scale, weight: .bold, design: .monospaced)).foregroundColor(color.opacity(bright ? 0.9 : 0.5)),
                     at: CGPoint(x: edge.x + (edge.x - center.x) / radiusPx * 30 * scale, y: edge.y + (edge.y - center.y) / radiusPx * 30 * scale))
        }
    }

    // MARK: aircraft

    private func drawTrail(_ ctx: inout GraphicsContext, _ ac: Aircraft, point: (Coordinate) -> CGPoint) {
        guard let pts = trails[ac.id], pts.count > 1 else { return }
        let c = ac.agreement.isDisputed ? disputedColor : altitudeColor(ac.altitudeFt)
        for i in 1..<pts.count {
            var seg = Path()
            seg.move(to: point(pts[i - 1])); seg.addLine(to: point(pts[i]))
            let fade = Double(i) / Double(pts.count)
            ctx.stroke(seg, with: .color(c.opacity(0.45 * fade)), lineWidth: 2 * scale)
        }
    }

    private func drawAircraft(_ ctx: inout GraphicsContext, _ placed: Placed) {
        let ac = placed.ac, p = placed.point
        let c = ac.agreement.isDisputed ? disputedColor : altitudeColor(ac.altitudeFt)
        let s = 20 * scale
        let age = firstSeen[ac.id].map { now.timeIntervalSince($0) } ?? 99
        var layer = ctx
        layer.opacity = min(1, max(0.0, age / 1.5))   // fade in when first seen

        // Airplane silhouette pointing up, rotated to track.
        var plane = Path()
        plane.move(to: CGPoint(x: 0, y: -s))
        plane.addLine(to: CGPoint(x: s * 0.16, y: -s * 0.35))
        plane.addLine(to: CGPoint(x: s * 0.95, y: s * 0.25))
        plane.addLine(to: CGPoint(x: s * 0.95, y: s * 0.45))
        plane.addLine(to: CGPoint(x: s * 0.16, y: s * 0.2))
        plane.addLine(to: CGPoint(x: s * 0.12, y: s * 0.7))
        plane.addLine(to: CGPoint(x: s * 0.4, y: s * 0.9))
        plane.addLine(to: CGPoint(x: s * 0.4, y: s * 1.0))
        plane.addLine(to: CGPoint(x: 0, y: s * 0.88))
        plane.addLine(to: CGPoint(x: -s * 0.4, y: s * 1.0))
        plane.addLine(to: CGPoint(x: -s * 0.4, y: s * 0.9))
        plane.addLine(to: CGPoint(x: -s * 0.12, y: s * 0.7))
        plane.addLine(to: CGPoint(x: -s * 0.16, y: s * 0.2))
        plane.addLine(to: CGPoint(x: -s * 0.95, y: s * 0.45))
        plane.addLine(to: CGPoint(x: -s * 0.95, y: s * 0.25))
        plane.addLine(to: CGPoint(x: -s * 0.16, y: -s * 0.35))
        plane.closeSubpath()

        var g = layer
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .degrees(ac.trackDeg ?? 0))
        g.fill(plane, with: .color(c))

        // Cross-check ring: solid when sources agree (stronger for 3), dashed red when they don't.
        let ring = Path(ellipseIn: CGRect(x: p.x - s * 1.5, y: p.y - s * 1.5, width: s * 3, height: s * 3))
        switch ac.agreement {
        case .confirmed where ac.confirmingSources >= 3:
            layer.stroke(ring, with: .color(c.opacity(0.6)), lineWidth: 2 * scale)
        case .confirmed:
            layer.stroke(ring, with: .color(c.opacity(0.3)), lineWidth: 1.5 * scale)
        case .disputed:
            layer.stroke(ring, with: .color(c.opacity(0.9)), style: StrokeStyle(lineWidth: 2 * scale, dash: [5 * scale, 4 * scale]))
        case .single: break
        }

        if placed.focus {
            // Selection brackets.
            let h = s * 2.1, l = s * 0.7
            var b = Path()
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                let corner = CGPoint(x: p.x + sx * h, y: p.y + sy * h)
                b.move(to: CGPoint(x: corner.x - sx * l, y: corner.y)); b.addLine(to: corner)
                b.addLine(to: CGPoint(x: corner.x, y: corner.y - sy * l))
            }
            layer.stroke(b, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round, lineJoin: .round))
        }

        if let r = placed.labelRect, let t1 = placed.line1 {
            layer.draw(t1, at: r.origin, anchor: .topLeading)
            if let t2 = placed.line2 {
                layer.draw(t2, at: CGPoint(x: r.minX, y: r.minY + t1.measure(in: CGSize(width: 800, height: 100)).height), anchor: .topLeading)
            }
        }
    }

    // MARK: HUD

    private func drawHUD(_ ctx: inout GraphicsContext, visible: [Aircraft]) {
        let margin = 56 * scale
        ctx.draw(Text(config.name.uppercased()).font(.system(size: 34 * scale, weight: .bold, design: .monospaced)).foregroundColor(ink.opacity(0.85)),
                 at: CGPoint(x: margin, y: margin), anchor: .topLeading)
        let confirmed = visible.filter { $0.sources.count > 1 && !$0.agreement.isDisputed }.count
        let disputed = visible.filter { $0.agreement.isDisputed }.count
        var summary = "\(visible.count) aircraft · \(confirmed) cross-checked"
        if disputed > 0 { summary += " · \(disputed) disputed" }
        ctx.draw(Text(summary).font(.system(size: 22 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.55)),
                 at: CGPoint(x: margin, y: margin + 46 * scale), anchor: .topLeading)

        // Source health, with how often each source has been the odd one out.
        var y = margin
        for id in SourceID.allCases.reversed() {
            let st = status[id]
            let live = st?.isLive(at: now) ?? false
            let dot = live ? Color(red: 0.4, green: 0.95, blue: 0.6) : Color(red: 1, green: 0.5, blue: 0.4)
            var text = live ? "\(id.rawValue)  \(st?.aircraftCount ?? 0)" : "\(id.rawValue)  \(st?.lastError ?? "connecting")"
            if live, let r = reliability[id] { text += "  \(Int((r * 100).rounded()))%" }
            let resolved = ctx.resolve(Text(text).font(.system(size: 20 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.55)))
            let w = resolved.measure(in: CGSize(width: 700, height: 60)).width
            ctx.draw(resolved, at: CGPoint(x: size.width - margin, y: y), anchor: .topTrailing)
            ctx.fill(Path(ellipseIn: CGRect(x: size.width - margin - w - 22 * scale, y: y + 5 * scale, width: 12 * scale, height: 12 * scale)),
                     with: .color(dot.opacity(0.9)))
            y += 30 * scale
        }

        // Feed warnings sit under the source list, out of the radar's way.
        switch feedHealth {
        case .down:
            ctx.draw(Text("NO LIVE DATA · feeds unreachable").font(.system(size: 22 * scale, weight: .bold, design: .monospaced)).foregroundColor(disputedColor),
                     at: CGPoint(x: size.width - margin, y: y + 8 * scale), anchor: .topTrailing)
        case .degraded:
            ctx.draw(Text("Reduced cross-checking").font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(Color(red: 1, green: 0.8, blue: 0.4).opacity(0.8)),
                     at: CGPoint(x: size.width - margin, y: y + 8 * scale), anchor: .topTrailing)
        case .live: break
        }
    }

    private func drawLegend(_ ctx: inout GraphicsContext) {
        let margin = 56 * scale
        let u = display.units
        let rows: [(Color, String)] = [
            (altitudeColor(2_000), "below \(u.altitude(5_000))"),
            (altitudeColor(10_000), "\(u.altitude(5_000)) – \(u.altitude(18_000))"),
            (altitudeColor(25_000), "\(u.altitude(18_000)) – \(u.altitude(30_000))"),
            (altitudeColor(35_000), "above \(u.altitude(30_000))"),
        ]
        let rowH = 28 * scale
        var y = size.height - margin - rowH * CGFloat(rows.count + 2)
        for (color, text) in rows {
            ctx.fill(Path(ellipseIn: CGRect(x: margin, y: y + 6 * scale, width: 14 * scale, height: 14 * scale)), with: .color(color.opacity(0.9)))
            ctx.draw(Text(text).font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.5)),
                     at: CGPoint(x: margin + 26 * scale, y: y), anchor: .topLeading)
            y += rowH
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: margin, y: y + 5 * scale, width: 16 * scale, height: 16 * scale)), with: .color(ink.opacity(0.5)), lineWidth: 1.5 * scale)
        ctx.draw(Text("2+ sources agree").font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.5)),
                 at: CGPoint(x: margin + 26 * scale, y: y), anchor: .topLeading)
        y += rowH
        ctx.stroke(Path(ellipseIn: CGRect(x: margin, y: y + 5 * scale, width: 16 * scale, height: 16 * scale)), with: .color(disputedColor),
                   style: StrokeStyle(lineWidth: 1.5 * scale, dash: [3 * scale, 3 * scale]))
        ctx.draw(Text("sources disagree").font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.5)),
                 at: CGPoint(x: margin + 26 * scale, y: y), anchor: .topLeading)
    }
}
