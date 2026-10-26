#if !os(tvOS)
import SwiftUI
import LiveAirspaceKit

/// Floating controls for touch and mouse (the Apple TV uses the remote instead).
public struct ControlBar: View {
    @ObservedObject var model: LiveAirspaceModel
    @ObservedObject var store: AirspaceStore
    var onSearch: () -> Void
    var onSettings: () -> Void
    var onWelcome: () -> Void

    /// Height the radar view should reserve at the bottom so its cards and legend sit above the bar.
    public static let reservedHeight: CGFloat = 76

    public init(model: LiveAirspaceModel, onSearch: @escaping () -> Void, onSettings: @escaping () -> Void, onWelcome: @escaping () -> Void) {
        self.model = model
        self.store = model.store
        self.onSearch = onSearch
        self.onSettings = onSettings
        self.onWelcome = onWelcome
    }

    public var body: some View {
        HStack(spacing: 4) {
            button("chevron.left", "Previous aircraft") { model.store.cycleSelection(-1) }
            button("chevron.right", "Next aircraft") { model.store.cycleSelection(1) }
            divider
            button("magnifyingglass", "Search", action: onSearch)
            button("minus.magnifyingglass", "Zoom out") { model.zoom(in: false) }
            button("plus.magnifyingglass", "Zoom in") { model.zoom(in: true) }
            divider
            Menu {
                if model.isAwayFromHome {
                    Button { model.recenter() } label: { Label("Return to home view", systemImage: "house") }
                }
                if let focus = store.focus {
                    if model.followID == focus.id {
                        Button { model.stopFollowing() } label: { Label("Stop following \(focus.displayName)", systemImage: "location.slash") }
                    } else {
                        Button { model.follow(focus.id) } label: { Label("Follow \(focus.displayName)", systemImage: "location") }
                    }
                }
                Button { model.cyclePlace() } label: { Label("Next location", systemImage: "location.viewfinder") }
                Button { model.saveCurrentView() } label: { Label("Save this view", systemImage: "bookmark") }
                Divider()
                Button(action: onSettings) { Label("Settings", systemImage: "gearshape") }
                Button(action: onWelcome) { Label("Welcome screen", systemImage: "sparkles") }
            } label: {
                Image(systemName: model.isAwayFromHome ? "ellipsis.circle.fill" : "ellipsis.circle")
                    .font(.system(size: 18, weight: .medium)).frame(width: 40, height: 40)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .foregroundStyle(Color(red: 0.55, green: 0.95, blue: 0.85))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 22).padding(.horizontal, 4)
    }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
#endif
