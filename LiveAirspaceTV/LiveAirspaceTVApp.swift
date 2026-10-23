import SwiftUI
import TVServices
import LiveAirspaceKit
import LiveAirspaceUI

@main
struct LiveAirspaceTVApp: App {
    @StateObject private var model = LiveAirspaceModel(sharesConfig: true)
    @State private var showSettings = false

    var body: some Scene {
        WindowGroup {
            LiveAirspaceView(model: model, ambient: true)
                .focusable()
                // Left/Right step through aircraft, Up/Down change the range,
                // Play/Pause cycles location (near me, then each airport), Select opens settings.
                .onMoveCommand { direction in
                    switch direction {
                    case .left: model.store.cycleSelection(-1)
                    case .right: model.store.cycleSelection(1)
                    case .up: model.zoom(in: true)
                    case .down: model.zoom(in: false)
                    @unknown default: break
                    }
                }
                .onPlayPauseCommand { model.cyclePlace() }
                .onTapGesture { showSettings = true }
                .fullScreenCover(isPresented: $showSettings) {
                    SettingsView(model: model) { showSettings = false }
                }
                .onOpenURL { url in
                    // liveairspace://aircraft/<hex> from a Top Shelf tile
                    if url.host == "aircraft", let hex = url.pathComponents.last, hex != "/" { model.store.select(hex) }
                }
                .onChange(of: model.store.config) { _, _ in TVTopShelfContentProvider.topShelfContentDidChange() }
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
}
