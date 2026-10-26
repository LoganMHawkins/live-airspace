import SwiftUI
import TVServices
import LiveAirspaceKit
import LiveAirspaceUI

private enum TVSheet: Identifiable {
    case menu, search, settings, welcome
    var id: Self { self }
}

@main
struct LiveAirspaceTVApp: App {
    @StateObject private var model = LiveAirspaceModel(sharesConfig: true)
    @State private var sheet: TVSheet?

    var body: some Scene {
        WindowGroup {
            LiveAirspaceView(model: model, ambient: true)
                .focusable()
                // Left/Right step through aircraft, Up/Down zoom, Play/Pause cycles location, Select opens the menu.
                // In explore mode the arrows pan and Play/Pause cycles the zoom.
                .onMoveCommand { direction in
                    if model.exploring {
                        switch direction {
                        case .left: model.panStep(dx: -1, dy: 0)
                        case .right: model.panStep(dx: 1, dy: 0)
                        case .up: model.panStep(dx: 0, dy: -1)
                        case .down: model.panStep(dx: 0, dy: 1)
                        @unknown default: break
                        }
                    } else {
                        switch direction {
                        case .left: model.store.cycleSelection(-1)
                        case .right: model.store.cycleSelection(1)
                        case .up: model.zoom(in: true)
                        case .down: model.zoom(in: false)
                        @unknown default: break
                        }
                    }
                }
                .onPlayPauseCommand { if model.exploring { model.cycleZoom() } else { model.cyclePlace() } }
                .onTapGesture { sheet = .menu }
                .fullScreenCover(item: $sheet) { which in
                    switch which {
                    case .menu: TVMenu(model: model) { sheet = $0 }
                    case .search: SearchView(model: model) { sheet = nil }
                    case .settings:
                        SettingsView(model: model, onShowWelcome: {
                            sheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.showWelcomeAgain() }
                        }) { sheet = nil }
                    case .welcome: WelcomeView(model: model) { sheet = nil }
                    }
                }
                .onOpenURL { url in
                    // liveairspace://aircraft/<hex> from a Top Shelf tile
                    if url.host == "aircraft", let hex = url.pathComponents.last, hex != "/" { model.store.select(hex) }
                }
                .onChange(of: model.store.config) { _, _ in TVTopShelfContentProvider.topShelfContentDidChange() }
                .onChange(of: model.settings.data.hasSeenWelcome) { _, seen in if !seen { sheet = .welcome } }
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    if !model.settings.data.hasSeenWelcome { sheet = .welcome }
                }
                .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
}

/// What Select opens on the Apple TV: search, explore mode and the rest.
private struct TVMenu: View {
    @ObservedObject var model: LiveAirspaceModel
    @ObservedObject var store: AirspaceStore
    var open: (TVSheet?) -> Void

    init(model: LiveAirspaceModel, open: @escaping (TVSheet?) -> Void) {
        self.model = model
        self.store = model.store
        self.open = open
    }

    var body: some View {
        VStack(spacing: 22) {
            Text("Live Airspace").font(.system(.largeTitle, design: .rounded, weight: .bold))
            VStack(spacing: 14) {
                row("Search", "magnifyingglass") { open(.search) }
                row(model.exploring ? "Stop exploring" : "Explore the map (pan and zoom)", "hand.draw") {
                    model.exploring.toggle()
                    open(nil)
                }
                if let focus = store.focus {
                    if model.followID == focus.id {
                        row("Stop following \(focus.displayName)", "location.slash") { model.stopFollowing(); open(nil) }
                    } else {
                        row("Follow \(focus.displayName)", "location") { model.follow(focus.id); open(nil) }
                    }
                }
                if model.isAwayFromHome {
                    row("Return to home view", "house") { model.recenter(); open(nil) }
                }
                row("Save this view", "bookmark") { model.saveCurrentView(); open(nil) }
                row("Settings", "gearshape") { open(.settings) }
                row("Close", "xmark") { open(nil) }
            }
            .frame(maxWidth: 900)
        }
        .padding(60)
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.title3, design: .rounded, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
    }
}
