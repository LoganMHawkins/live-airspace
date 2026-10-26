import SwiftUI
import LiveAirspaceKit

/// First-launch welcome: what Live Airspace does, then where to look first.
public struct WelcomeView: View {
    @ObservedObject var model: LiveAirspaceModel
    var allowsNearMe: Bool
    var onFinish: () -> Void
    @State private var page = 0

    public init(model: LiveAirspaceModel, allowsNearMe: Bool = true, onFinish: @escaping () -> Void) {
        self.model = model
        self.allowsNearMe = allowsNearMe
        self.onFinish = onFinish
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                RadarBackdrop()
                ViewThatFits(in: .vertical) {
                    content(compact: false)
                    content(compact: true)
                }
                .frame(maxWidth: contentWidth)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 640)
        #endif
    }

    private var contentWidth: CGFloat {
        #if os(tvOS)
        return 1100
        #else
        return 520
        #endif
    }

    @ViewBuilder private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 16 : 26) {
            Spacer(minLength: 0)
            if page == 0 { intro(compact: compact) } else { whereToLook(compact: compact) }
            Spacer(minLength: 0)
            pageDots
        }
        .padding(.horizontal, 28)
        .padding(.vertical, compact ? 18 : 32)
        .animation(.smooth(duration: 0.35), value: page)
    }

    // MARK: page 1

    private func intro(compact: Bool) -> some View {
        VStack(spacing: compact ? 16 : 24) {
            RadarMark(size: compact ? 84 : 112)
                .modifier(WelcomeEntrance(order: 0))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Welcome to Live Airspace")
                    .font(.system(compact ? .title : .largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .accessibilityAddTraits(.isHeader)
                    .modifier(WelcomeEntrance(order: 1))
                Text("Every aircraft overhead, cross-checked.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                    .modifier(WelcomeEntrance(order: 1.4))
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                feature("checkmark.shield", Theme.green, "Cross-checked traffic",
                        "Three independent live feeds, compared in real time. When they disagree, you see it.", order: 2)
                feature(interactionSymbol, Theme.cyan, interactionTitle, interactionDetail, order: 3)
                feature("magnifyingglass", Theme.violet, "Search anywhere",
                        "Find a flight, airport or city, then follow it across the sky.", order: 4)
            }
            .frame(maxWidth: 440, alignment: .leading)

            VStack(spacing: 10) {
                Label("Your location only chooses the area shown. No accounts, no tracking.", systemImage: "lock.fill")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .modifier(WelcomeEntrance(order: 5))
                Label("Free community data. Not for navigation.", systemImage: "exclamationmark.triangle")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.amber)
                    .modifier(WelcomeEntrance(order: 5.4))
                Button { withAnimation { page = 1 } } label: {
                    Text("Continue").font(.system(.headline, design: .rounded)).foregroundStyle(.black.opacity(0.85)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .accentButton()
                .controlSize(.large)
                .modifier(WelcomeEntrance(order: 6))
            }
            .frame(maxWidth: 440)
        }
    }

    private var interactionSymbol: String {
        #if os(tvOS)
        return "appletvremote.gen4"
        #elseif os(macOS)
        return "cursorarrow.motionlines"
        #else
        return "hand.tap"
        #endif
    }

    private var interactionTitle: String {
        #if os(tvOS)
        return "Made for the remote"
        #elseif os(macOS)
        return "Click, drag and scroll"
        #else
        return "Tap, drag and pinch"
        #endif
    }

    private var interactionDetail: String {
        #if os(tvOS)
        return "Left and right step through aircraft. Up and down zoom. Select opens search, explore mode and settings."
        #elseif os(macOS)
        return "Click an aircraft for its airline, route and photo. Drag to pan; pinch or scroll to zoom."
        #else
        return "Tap an aircraft for its airline, route and photo. Drag to pan and pinch to zoom."
        #endif
    }

    // MARK: page 2

    private func whereToLook(compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 22) {
            Image(systemName: "scope")
                .font(.system(size: compact ? 40 : 52, weight: .light))
                .foregroundStyle(Theme.ink)
                .modifier(WelcomeEntrance(order: 0))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Where should we look first?")
                    .font(.system(compact ? .title2 : .title, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .accessibilityAddTraits(.isHeader)
                    .modifier(WelcomeEntrance(order: 0.5))
                Text("You can change this any time, or search anywhere in the world.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                    .modifier(WelcomeEntrance(order: 1))
            }
            .multilineTextAlignment(.center)

            if allowsNearMe {
                Button { choose(.nearMe) } label: {
                    Label("Use my location", systemImage: "location.fill")
                        .font(.system(.headline, design: .rounded)).foregroundStyle(.black.opacity(0.85)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .accentButton()
                .controlSize(.large)
                .frame(maxWidth: 440)
                .modifier(WelcomeEntrance(order: 1.5))
            }

            VStack(spacing: 8) {
                Text(allowsNearMe ? "Or pick a busy airport" : "Pick a busy airport")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(AirspaceConfig.presets, id: \.name) { preset in
                        Button { choose(.preset(preset.name)) } label: {
                            Text(preset.name).font(.system(.subheadline, design: .rounded, weight: .medium)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.ink)
                    }
                }
            }
            .frame(maxWidth: 440)
            .modifier(WelcomeEntrance(order: 2))

            HStack(spacing: 20) {
                Button("Back") { withAnimation { page = 0 } }
                Button("Decide later") { choose(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Theme.secondary)
            .modifier(WelcomeEntrance(order: 3))
        }
    }

    private func choose(_ place: Place?) {
        if let place { model.setPlace(place) }
        model.completeWelcome()
        onFinish()
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { i in
                Circle().fill(i == page ? Theme.ink : Color.white.opacity(0.25)).frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, order: Int) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(.title2, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .modifier(WelcomeSymbolEntrance(order: order))
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.primary)
                    .modifier(WelcomeEntrance(order: Double(order)))
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.secondary)
                    .modifier(WelcomeEntrance(order: Double(order) + 0.4))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The app mark: a radar scope with a sweep and a plane.
private struct RadarMark: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = min(canvas.width, canvas.height) / 2
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.02, green: 0.05, blue: 0.07)))
                for i in 1...3 {
                    let rr = r * CGFloat(i) / 3
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(Theme.ink.opacity(0.22)), lineWidth: 1.2)
                }
                // Sweep: a fading wedge trailing a bright leading edge.
                let angle = reduceMotion ? 0.8 : t * 1.6
                for k in 0..<28 {
                    let a0 = angle - Double(k) * 0.045, a1 = a0 - 0.045
                    var wedge = Path()
                    wedge.move(to: c)
                    wedge.addArc(center: c, radius: r, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: false)
                    ctx.fill(wedge, with: .color(Theme.ink.opacity(0.28 * (1 - Double(k) / 28))))
                }
                // Plane, heading north-east.
                var plane = Path()
                let s = r * 0.42
                let pts: [(CGFloat, CGFloat)] = [(0, -1), (0.16, -0.35), (0.95, 0.25), (0.95, 0.45), (0.16, 0.2), (0.12, 0.7), (0.4, 0.9), (0.4, 1.0), (0, 0.88), (-0.4, 1.0), (-0.4, 0.9), (-0.12, 0.7), (-0.16, 0.2), (-0.95, 0.45), (-0.95, 0.25), (-0.16, -0.35)]
                for (i, q) in pts.enumerated() { let p = CGPoint(x: q.0 * s, y: q.1 * s); i == 0 ? plane.move(to: p) : plane.addLine(to: p) }
                plane.closeSubpath()
                var layer = ctx
                layer.translateBy(x: c.x, y: c.y)
                layer.rotate(by: .degrees(45))
                layer.fill(plane, with: .color(Theme.cyan))
                // An amber blip that pulses.
                let pulse = reduceMotion ? 1.0 : 0.6 + 0.4 * sin(t * 3)
                let b = CGPoint(x: c.x + r * 0.55, y: c.y + r * 0.42)
                ctx.fill(Path(ellipseIn: CGRect(x: b.x - 4, y: b.y - 4, width: 8, height: 8)), with: .color(Theme.amber.opacity(pulse)))
            }
            .frame(width: size, height: size)
            .shadow(color: Theme.cyan.opacity(0.35), radius: 18)
        }
    }
}

/// A faint, slowly sweeping radar behind the welcome pages.
private struct RadarBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let r = max(size.width, size.height) * 0.7
                for i in 1...5 {
                    let rr = r * CGFloat(i) / 5
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(Theme.ink.opacity(0.06)), lineWidth: 1)
                }
                let a = reduceMotion ? 0.5 : t * 0.5
                var line = Path()
                line.move(to: c)
                line.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                ctx.stroke(line, with: .color(Theme.ink.opacity(0.10)), lineWidth: 2)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Gives each text block an initial hidden state before starting its entrance.
private struct WelcomeEntrance: ViewModifier {
    let order: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .task {
                do {
                    if !reduceMotion { try await Task.sleep(for: .seconds(0.25 + order * 0.12)) }
                    try Task.checkCancellation()
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.6)) { visible = true }
                } catch {}
            }
    }
}

/// Draws each symbol on just after its title starts to appear (where the system supports draw-on), otherwise fades it in.
private struct WelcomeSymbolEntrance: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, macOS 26, tvOS 26, *) {
                content.symbolEffect(.drawOn.byLayer, isActive: !revealed && !reduceMotion)
            } else {
                content.opacity(revealed || reduceMotion ? 1 : 0)
            }
        }
        .task {
            guard !reduceMotion else { revealed = true; return }
            try? await Task.sleep(for: .seconds(0.4 + Double(order) * 0.3))
            withAnimation(.easeOut(duration: 0.4)) { revealed = true }
        }
    }
}
