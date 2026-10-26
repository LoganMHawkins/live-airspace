import SwiftUI
import MapKit
import LiveAirspaceKit
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen radar-style live traffic display. Shared by the tvOS app, the iOS/iPadOS/macOS app and the macOS screen saver.
public struct LiveAirspaceView: View {
    @ObservedObject var model: LiveAirspaceModel
    @ObservedObject var store: AirspaceStore
    @ObservedObject var settings: AppSettings
    var ambient: Bool
    var controlsInset: CGFloat
    /// Live gesture state: the map follows the finger immediately and is committed to the model when the gesture ends.
    @State private var panOffset: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var wheelCommit: Task<Void, Never>?

    /// - Parameters:
    ///   - ambient: slowly drifts the HUD and map and dims static elements to protect OLED/plasma panels.
    ///   - controlsInset: height reserved at the bottom for an app-provided control bar, so cards and the legend sit above it.
    public init(model: LiveAirspaceModel, ambient: Bool = true, controlsInset: CGFloat = 0) {
        self.model = model
        self.store = model.store
        self.settings = model.settings
        self.ambient = ambient
        self.controlsInset = controlsInset
    }

    public var body: some View {
        let display = settings.data.display
        let focus = store.focus
        // This reader sits inside the safe area so it can report the real insets (notch, status bar, home indicator);
        // the content below is then laid out over the whole screen, with those insets used to pad the HUD.
        GeometryReader { outer in
            let insets = Self.safeInsets(outer.safeAreaInsets)
            let full = CGSize(width: outer.size.width + outer.safeAreaInsets.leading + outer.safeAreaInsets.trailing,
                              height: outer.size.height + outer.safeAreaInsets.top + outer.safeAreaInsets.bottom)
            let geo = (size: full, safeAreaInsets: insets)
            let scale = displayScale(for: geo.size)
            let margin = 56 * scale
            let leading = margin + insets.leading, trailing = margin + insets.trailing
            let cardWidth = min(568 * scale, geo.size.width - leading - trailing)
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let camera = model.cameraCenter(at: timeline.date)
                ZStack {
                    if display.mapOpacity > 0 {
                        MapLayer(config: store.config, camera: camera, pan: panOffset, zoom: pinch, size: geo.size,
                                 ambient: ambient, opacity: display.mapOpacity, style: display.mapStyle, now: timeline.date)
                    }
                    Canvas { context, size in
                        Renderer(
                            context: context, size: size, now: timeline.date,
                            aircraft: store.aircraft, trails: store.trails, firstSeen: store.firstSeen,
                            status: store.status, reliability: store.reliability, feedHealth: store.feedHealth,
                            enabledSources: store.enabledSources,
                            details: store.details, focusID: focus?.id,
                            airports: display.showAirports ? AirportDatabase.near(camera, radiusNM: store.config.radiusNM * 2) : [],
                            config: store.config, camera: camera, pan: panOffset, zoom: pinch,
                            display: display, ambient: ambient,
                            inset: insets, bottomExtra: controlsInset
                        ).draw()
                    }
                    // Cards ride the same slow drift as the radar.
                    ZStack {
                        if let alert = store.activeAlert {
                            AlertBanner(alert: alert, scale: scale)
                                .padding(.top, (isCompact(geo.size) ? 100 : 150) * scale + insets.top)
                                .padding(.horizontal, margin / 2)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        #if os(tvOS)
                        if model.exploring {
                            ExploreBanner(scale: scale)
                                .padding(.top, 54 * scale)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        #endif
                        if let focus {
                            InfoCard(aircraft: focus, details: store.details[focus.id], config: store.config,
                                     units: display.units, scale: scale, now: timeline.date,
                                     width: cardWidth, compact: isCompact(geo.size),
                                     following: model.followID == focus.id,
                                     showDistance: model.followID == nil,
                                     onFollow: { model.followID == focus.id ? model.stopFollowing() : model.follow(focus.id) })
                                .padding(EdgeInsets(top: 0, leading: leading, bottom: margin + insets.bottom + controlsInset, trailing: trailing))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: store.activeAlert)
                    .offset(ambient ? ambientDrift(at: timeline.date, scale: scale) : .zero)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(x: -outer.safeAreaInsets.leading, y: -outer.safeAreaInsets.top)
                #if !os(tvOS)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { select(at: $0.location, size: geo.size, camera: camera) })
                .simultaneousGesture(DragGesture(minimumDistance: 8)
                    .onChanged { panOffset = $0.translation }
                    .onEnded { value in commitPan(value.translation, size: geo.size) })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { value in
                        let r = store.config.radiusNM
                        pinch = min(max(value.magnification, r / LiveAirspaceModel.maxRadiusNM), r / LiveAirspaceModel.minRadiusNM)
                    }
                    .onEnded { _ in commitPinch() })
                #endif
            }
        }
        .background(Color(red: 0.01, green: 0.02, blue: 0.03).ignoresSafeArea())
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        #if !os(tvOS)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { handleKey($0) }
        #endif
        #if os(macOS)
        // Trackpad two-finger scroll pans; a mouse wheel zooms.
        .background(ScrollMonitor { dx, dy, precise, ended in
            if precise {
                panOffset.width += dx
                panOffset.height += dy
                if ended { commitPan(panOffset, size: NSApp.keyWindow?.contentView?.bounds.size ?? CGSize(width: 1000, height: 700)) }
            } else {
                let r = store.config.radiusNM
                pinch = min(max(pinch * exp(dy * 0.04), r / LiveAirspaceModel.maxRadiusNM), r / LiveAirspaceModel.minRadiusNM)
                wheelCommit?.cancel()
                wheelCommit = Task { try? await Task.sleep(for: .milliseconds(350)); if !Task.isCancelled { commitPinch() } }
            }
        })
        #endif
    }

    /// The Apple TV layout is designed edge to edge with its own margins, so it ignores the (large) tvOS safe area.
    private static func safeInsets(_ insets: EdgeInsets) -> EdgeInsets {
        #if os(tvOS)
        return EdgeInsets()
        #else
        return insets
        #endif
    }

    #if !os(tvOS)
    private func commitPan(_ translation: CGSize, size: CGSize) {
        panOffset = .zero
        guard abs(translation.width) > 2 || abs(translation.height) > 2 else { return }
        let pxPerNM = min(size.width, size.height) / 2 * 0.86 / store.config.radiusNM
        model.pan(eastNM: -translation.width / pxPerNM, northNM: translation.height / pxPerNM)
    }

    private func commitPinch() {
        let zoom = pinch
        pinch = 1
        guard abs(zoom - 1) > 0.02 else { return }
        model.setRadius(store.config.radiusNM / zoom)
    }

    /// Selects the aircraft nearest the touch if it's within about a fingertip; otherwise clears the selection.
    private func select(at point: CGPoint, size: CGSize, camera: Coordinate) {
        let center = CGPoint(x: size.width / 2 + panOffset.width, y: size.height / 2 + panOffset.height)
        let pxPerNM = min(size.width, size.height) / 2 * 0.86 * pinch / store.config.radiusNM
        let now = Date()
        var best: (id: String, distance: CGFloat)?
        for ac in store.aircraft where !ac.onGround {
            let o = Geo.offsetNM(from: camera, to: ac.position(at: now))
            let p = CGPoint(x: center.x + o.east * pxPerNM, y: center.y - o.north * pxPerNM)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < 44, d < (best?.distance ?? .infinity) { best = (ac.id, d) }
        }
        if let best {
            if model.followID != nil, model.followID != best.id { model.stopFollowing() }
            store.select(best.id)
            Haptics.selection()
        } else {
            store.clearSelection()
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let shift = press.modifiers.contains(.shift)
        switch press.key {
        case .leftArrow: if shift { model.panStep(dx: -1, dy: 0) } else { store.cycleSelection(-1) }
        case .rightArrow: if shift { model.panStep(dx: 1, dy: 0) } else { store.cycleSelection(1) }
        case .upArrow: if shift { model.panStep(dx: 0, dy: -1) } else { model.zoom(in: true) }
        case .downArrow: if shift { model.panStep(dx: 0, dy: 1) } else { model.zoom(in: false) }
        case .escape: model.stopFollowing(); store.clearSelection()
        default:
            switch press.characters {
            case "+", "=": model.zoom(in: true)
            case "-", "_": model.zoom(in: false)
            case "0", "h": model.recenter()
            case "f": if let id = store.focus?.id { model.followID == id ? model.stopFollowing() : model.follow(id) }
            default: return .ignored
            }
        }
        return .handled
    }
    #endif
}

#if os(macOS)
import AppKit

/// Reports scroll-wheel events over the window (SwiftUI has no scroll gesture on the Mac).
private struct ScrollMonitor: NSViewRepresentable {
    var handler: (_ dx: CGFloat, _ dy: CGFloat, _ precise: Bool, _ ended: Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { context.coordinator.handler = handler }
    func makeCoordinator() -> Coordinator { Coordinator(handler: handler) }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    final class Coordinator {
        var handler: (CGFloat, CGFloat, Bool, Bool) -> Void
        private var monitor: Any?
        init(handler: @escaping (CGFloat, CGFloat, Bool, Bool) -> Void) { self.handler = handler }

        func install(on view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window else { return event }
                // Ignore momentum after the fingers lift; the pan is committed when the touch phase ends.
                if event.momentumPhase != [] { return event }
                let ended = event.phase == .ended || event.phase == .cancelled
                self.handler(event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas, ended)
                return event
            }
        }

        func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { remove() }
    }
}
#endif

#if canImport(UIKit) && !os(tvOS)
/// A light tap when an aircraft is selected.
enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
#else
enum Haptics { static func selection() {} }
#endif

// MARK: - shared bits

/// Points-per-design-unit. tvOS is laid out for a 1080-point screen seen from a couch, so it scales with the screen;
/// handheld and desktop use fixed, smaller type.
func displayScale(for size: CGSize) -> CGFloat {
    #if os(tvOS)
    return max(size.height / 1080, 0.5)
    #elseif os(iOS)
    return UIDevice.current.userInterfaceIdiom == .pad ? 0.8 : 0.62
    #else
    return 0.75
    #endif
}

/// Phones (either orientation): shorter text, no photo or legend.
func isCompact(_ size: CGSize) -> Bool {
    #if os(tvOS)
    return false
    #else
    return min(size.width, size.height) < 500
    #endif
}

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

/// Map aligned to the radar's projection: radar centre = camera, same nm-per-point scale.
private struct MapLayer: View {
    var config: AirspaceConfig
    var camera: Coordinate
    /// In-progress drag and pinch, applied as a transform so the map follows the finger before the view is committed.
    var pan: CGSize
    var zoom: CGFloat
    var size: CGSize
    var ambient: Bool
    var opacity: Double
    var style: MapStyleChoice
    var now: Date

    var body: some View {
        let scale = displayScale(for: size)
        // Oversized so drift and panning never expose an edge.
        let pad = 80 * scale
        let mapSize = CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
        let pxPerNM = min(size.width, size.height) / 2 * 0.86 / config.radiusNM
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude),
            latitudinalMeters: min(mapSize.height / pxPerNM * 1852, 20_000_000),
            longitudinalMeters: min(mapSize.width / pxPerNM * 1852, 20_000_000))
        // In ambient mode the map slowly breathes between full and ~55% strength so no tile stays at one brightness.
        let t = now.timeIntervalSinceReferenceDate
        let breathe = ambient ? 0.775 + 0.225 * sin(t / 95) : 1

        // The map sits in an overlay and is clipped, otherwise its oversize frame would stretch the whole stack
        // and push the radar and cards off-screen.
        Color.clear
            .overlay(
                Map(position: .constant(.region(region)), interactionModes: [])
                    .mapStyle(style == .satellite ? .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
                                                  : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .environment(\.colorScheme, style == .light ? .light : .dark)
                    .frame(width: mapSize.width, height: mapSize.height)
                    .scaleEffect(zoom)
                    .opacity(opacity * breathe)
                    .offset(CGSize(width: pan.width + (ambient ? ambientDrift(at: now, scale: scale).width : 0),
                                   height: pan.height + (ambient ? ambientDrift(at: now, scale: scale).height : 0)))
            )
            .frame(width: size.width, height: size.height)
            .clipped()
            .allowsHitTesting(false)
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

#if os(tvOS)
private struct ExploreBanner: View {
    var scale: CGFloat
    var body: some View {
        HStack(spacing: 16 * scale) {
            Image(systemName: "hand.draw").font(.system(size: 30 * scale))
            Text("EXPLORE  ·  arrows pan  ·  ⏯ zoom  ·  Select for menu")
                .font(.system(size: 22 * scale, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(.black)
        .padding(.horizontal, 28 * scale).padding(.vertical, 14 * scale)
        .background(Capsule().fill(ink))
    }
}
#endif

private struct InfoCard: View {
    var aircraft: Aircraft
    var details: AircraftDetails?
    var config: AirspaceConfig
    var units: Units
    var scale: CGFloat
    var now: Date
    var width: CGFloat
    var compact: Bool
    var following = false
    var showDistance = true
    var onFollow: () -> Void = {}

    var body: some View {
        let color = aircraft.agreement.isDisputed ? disputedColor : altitudeColor(aircraft.altitudeFt)
        let distance = Geo.distanceNM(config.center, aircraft.position(at: now))
        VStack(alignment: .leading, spacing: 10 * scale) {
            if !compact, let url = details?.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: width - 48 * scale, height: 230 * scale)
                            .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                            .opacity(0.9)
                    case .empty:
                        RoundedRectangle(cornerRadius: 14 * scale).fill(Color.white.opacity(0.05))
                            .frame(width: width - 48 * scale, height: 230 * scale)
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
                #if !os(tvOS)
                Spacer(minLength: 0)
                Button(action: onFollow) {
                    Image(systemName: following ? "location.fill" : "location")
                        .font(.system(size: 20 * max(scale, 0.8), weight: .semibold))
                        .foregroundStyle(following ? Color.black : color)
                        .padding(8)
                        .background(Circle().fill(following ? color : color.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(following ? "Stop following" : "Follow this aircraft")
                .help(following ? "Stop following" : "Follow this aircraft")
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20 * max(scale, 0.8), weight: .semibold))
                        .foregroundStyle(color)
                        .padding(8)
                        .background(Circle().fill(color.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")
                #endif
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
            Text(stats(distance: showDistance ? distance : nil)).font(.system(size: 22 * scale, design: .monospaced)).foregroundColor(color.opacity(0.9))
            Text(crossCheck).font(.system(size: 18 * scale, design: .monospaced))
                .foregroundColor(aircraft.agreement.isDisputed ? disputedColor : ink.opacity(0.55))
        }
        .padding(24 * scale)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22 * scale).fill(Color.black.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 22 * scale).stroke(color.opacity(0.35), lineWidth: 1.5 * scale))
    }

    private func stats(distance: Double?) -> String {
        var parts: [String] = []
        if let alt = aircraft.altitudeFt { parts.append(units.altitude(alt) + (aircraft.altitudeDisputed ? "?" : "")) }
        if let gs = aircraft.groundSpeedKt { parts.append(units.speed(gs)) }
        if let vr = aircraft.verticalRateFpm, abs(vr) > 300 { parts.append((vr > 0 ? "↑ " : "↓ ") + units.rate(vr)) }
        if let distance { parts.append(units.distance(distance)) }
        return parts.joined(separator: " · ")
    }

    private var shareText: String {
        var parts = [aircraft.displayName]
        if let airline = details?.airline { parts.append(airline) }
        if let o = details?.origin, let d = details?.destination { parts.append("\(o.code) to \(d.code)") }
        if let type = details?.typeName ?? aircraft.typeCode { parts.append(type) }
        if let alt = aircraft.altitudeFt { parts.append(units.altitude(alt)) }
        return parts.joined(separator: " · ") + " — spotted on Live Airspace"
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
    var enabledSources: [SourceID]
    var details: [String: AircraftDetails]
    var focusID: String?
    var airports: [Airport]
    var config: AirspaceConfig
    /// Where the radar is looking, which can differ from `config.center` while following an aircraft.
    var camera: Coordinate
    var pan: CGSize
    var zoom: CGFloat
    var display: DisplaySettings
    var ambient: Bool
    var inset: EdgeInsets
    var bottomExtra: CGFloat

    private var scale: CGFloat { displayScale(for: size) }
    private var compact: Bool { isCompact(size) }
    /// Distance from each screen edge to the HUD: the standard margin plus the device safe area (and the app's control bar at the bottom).
    private var edge: (l: CGFloat, t: CGFloat, r: CGFloat, b: CGFloat) {
        let m = 56 * scale
        return (m + inset.leading, m + inset.top, m + inset.trailing, m + inset.bottom + bottomExtra)
    }
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

        let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
        let radiusPx = min(size.width, size.height) / 2 * 0.86 * zoom
        let pxPerNM = radiusPx / config.radiusNM

        func point(_ c: Coordinate) -> CGPoint {
            let o = Geo.offsetNM(from: camera, to: c)
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
        let byDistance = visible.sorted { Geo.distanceNM(camera, $0.position(at: now)) < Geo.distanceNM(camera, $1.position(at: now)) }
        let s = 20 * scale
        var result: [Placed] = byDistance.map {
            Placed(ac: $0, point: point($0.position(at: now)), focus: $0.id == focusID)
        }
        // Reserve every aircraft icon so labels never cover a neighbour.
        var rects = result.map { CGRect(x: $0.point.x - s * 1.2, y: $0.point.y - s * 1.2, width: s * 2.4, height: s * 2.4) }
        // Keep labels clear of the info card in the bottom-right corner (card is 568 wide and about 600 tall with a photo).
        let e = edge
        let cardW = min(568 * scale, size.width - e.l - e.r), cardH = (compact ? 330 : 620) * scale
        let cardRect = CGRect(x: size.width - e.r - cardW, y: size.height - e.b - cardH, width: cardW, height: cardH)
        rects.append(cardRect)
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
            case .all where !isFocus && rank >= (config.radiusNM > 100 ? 25 : 60): continue  // measuring text for hundreds of labels every frame is too slow
            default: break
            }
            let (l1, l2) = labelStrings(result[i].ac)
            let color = result[i].ac.agreement.isDisputed ? disputedColor : altitudeColor(result[i].ac.altitudeFt)
            let t1 = ctx.resolve(Text(l1).font(.system(size: 22 * scale, weight: .semibold, design: .monospaced)).foregroundColor(color))
            let t2 = ctx.resolve(Text(l2).font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(color.opacity(0.7)))
            let m1 = t1.measure(in: CGSize(width: 800, height: 100)), m2 = t2.measure(in: CGSize(width: 800, height: 100))
            let w = max(m1.width, m2.width), h = m1.height + (l2.isEmpty ? 0 : m2.height)
            // Sideways gaps are wider so the 6-point collision margin doesn't count the plane's own icon as an obstacle.
            let p = result[i].point, gap = s * 1.4, gapX = s * 1.7
            let candidates = [
                CGRect(x: p.x + gapX, y: p.y - h / 2, width: w, height: h),
                CGRect(x: p.x - gapX - w, y: p.y - h / 2, width: w, height: h),
                CGRect(x: p.x - w / 2, y: p.y - gap - h, width: w, height: h),
                CGRect(x: p.x - w / 2, y: p.y + gap, width: w, height: h),
            ]
            let fit = candidates.first { r in bounds.contains(r) && !rects.contains { $0.intersects(r.insetBy(dx: -6 * scale, dy: -3 * scale)) } }
            // The selected aircraft always gets a label; if nothing is free, at least keep it out from under the info card.
            if let r = fit ?? (isFocus ? (candidates.first { !$0.intersects(cardRect) } ?? candidates[0]) : nil) {
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
        let s = 20 * scale * CGFloat(ac.sizeFactor)  // light aircraft smaller, heavies larger
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
        if ac.isRotorcraft {
            // Helicopter: fuselage, tail boom and a spinning rotor.
            var body = Path(ellipseIn: CGRect(x: -s * 0.32, y: -s * 0.55, width: s * 0.64, height: s * 1.0))
            body.addRect(CGRect(x: -s * 0.07, y: s * 0.35, width: s * 0.14, height: s * 0.85))
            body.addRect(CGRect(x: -s * 0.3, y: s * 1.05, width: s * 0.6, height: s * 0.12))
            g.fill(body, with: .color(c))
            var rotor = g
            rotor.rotate(by: .radians(now.timeIntervalSinceReferenceDate * 9))
            var blades = Path()
            blades.move(to: CGPoint(x: -s * 1.05, y: 0)); blades.addLine(to: CGPoint(x: s * 1.05, y: 0))
            blades.move(to: CGPoint(x: 0, y: -s * 1.05)); blades.addLine(to: CGPoint(x: 0, y: s * 1.05))
            rotor.stroke(blades, with: .color(c.opacity(0.7)), lineWidth: 2 * scale)
        } else {
            g.fill(plane, with: .color(c))
        }

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
        let e = edge
        ctx.draw(Text(config.name.uppercased()).font(.system(size: 34 * scale, weight: .bold, design: .monospaced)).foregroundColor(ink.opacity(0.85)),
                 at: CGPoint(x: e.l, y: e.t), anchor: .topLeading)
        let confirmed = visible.filter { $0.sources.count > 1 && !$0.agreement.isDisputed }.count
        let disputed = visible.filter { $0.agreement.isDisputed }.count
        var summary = compact ? "\(visible.count) aircraft" : "\(visible.count) aircraft · \(confirmed) cross-checked"
        if disputed > 0 { summary += " · \(disputed) disputed" }
        ctx.draw(Text(summary).font(.system(size: 22 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.55)),
                 at: CGPoint(x: e.l, y: e.t + 46 * scale), anchor: .topLeading)

        // Source health, with how often each source has been the odd one out.
        var y = e.t
        for id in enabledSources.reversed() {
            let st = status[id]
            let live = st?.isLive(at: now) ?? false
            let dot = live ? Color(red: 0.4, green: 0.95, blue: 0.6) : Color(red: 1, green: 0.5, blue: 0.4)
            var text = live ? "\(id.rawValue)  \(st?.aircraftCount ?? 0)" : "\(id.rawValue)  \(st?.lastError ?? "connecting")"
            if live, !compact, let r = reliability[id] { text += "  \(Int((r * 100).rounded()))%" }
            let resolved = ctx.resolve(Text(text).font(.system(size: 20 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.55)))
            let w = resolved.measure(in: CGSize(width: 700, height: 60)).width
            ctx.draw(resolved, at: CGPoint(x: size.width - e.r, y: y), anchor: .topTrailing)
            ctx.fill(Path(ellipseIn: CGRect(x: size.width - e.r - w - 22 * scale, y: y + 5 * scale, width: 12 * scale, height: 12 * scale)),
                     with: .color(dot.opacity(0.9)))
            y += 30 * scale
        }

        // Feed warnings sit under the source list, out of the radar's way.
        switch feedHealth {
        case .down:
            ctx.draw(Text("NO LIVE DATA · feeds unreachable").font(.system(size: 22 * scale, weight: .bold, design: .monospaced)).foregroundColor(disputedColor),
                     at: CGPoint(x: size.width - e.r, y: y + 8 * scale), anchor: .topTrailing)
        case .degraded:
            ctx.draw(Text("Reduced cross-checking").font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(Color(red: 1, green: 0.8, blue: 0.4).opacity(0.8)),
                     at: CGPoint(x: size.width - e.r, y: y + 8 * scale), anchor: .topTrailing)
        case .live: break
        }
    }

    private func drawLegend(_ ctx: inout GraphicsContext) {
        guard !compact else { return }  // no room on a phone
        let e = edge
        let u = display.units
        let rows: [(Color, String)] = [
            (altitudeColor(2_000), "below \(u.altitude(5_000))"),
            (altitudeColor(10_000), "\(u.altitude(5_000)) – \(u.altitude(18_000))"),
            (altitudeColor(25_000), "\(u.altitude(18_000)) – \(u.altitude(30_000))"),
            (altitudeColor(35_000), "above \(u.altitude(30_000))"),
        ]
        let rowH = 28 * scale
        var y = size.height - e.b - rowH * CGFloat(rows.count + 2)
        for (color, text) in rows {
            ctx.fill(Path(ellipseIn: CGRect(x: e.l, y: y + 6 * scale, width: 14 * scale, height: 14 * scale)), with: .color(color.opacity(0.9)))
            ctx.draw(Text(text).font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.5)),
                     at: CGPoint(x: e.l + 26 * scale, y: y), anchor: .topLeading)
            y += rowH
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: e.l, y: y + 5 * scale, width: 16 * scale, height: 16 * scale)), with: .color(ink.opacity(0.5)), lineWidth: 1.5 * scale)
        ctx.draw(Text("2+ sources agree").font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.5)),
                 at: CGPoint(x: e.l + 26 * scale, y: y), anchor: .topLeading)
        y += rowH
        ctx.stroke(Path(ellipseIn: CGRect(x: e.l, y: y + 5 * scale, width: 16 * scale, height: 16 * scale)), with: .color(disputedColor),
                   style: StrokeStyle(lineWidth: 1.5 * scale, dash: [3 * scale, 3 * scale]))
        ctx.draw(Text("sources disagree").font(.system(size: 18 * scale, design: .monospaced)).foregroundColor(ink.opacity(0.5)),
                 at: CGPoint(x: e.l + 26 * scale, y: y), anchor: .topLeading)
    }
}
