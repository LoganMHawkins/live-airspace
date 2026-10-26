import SwiftUI
import LiveAirspaceKit
import LiveAirspaceUI
#if canImport(UIKit)
import UIKit
#endif

/// iPhone, iPad and Mac app. One SwiftUI target for all three; the Apple TV and the screen saver have their own.
@main
struct LiveAirspaceApp: App {
    @StateObject private var model = LiveAirspaceModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 420)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Airspace") {
                Button("Next Aircraft") { model.store.cycleSelection(1) }.keyboardShortcut("]")
                Button("Previous Aircraft") { model.store.cycleSelection(-1) }.keyboardShortcut("[")
                Divider()
                Button("Zoom In") { model.zoom(in: true) }.keyboardShortcut("=")
                Button("Zoom Out") { model.zoom(in: false) }.keyboardShortcut("-")
                Divider()
                Button("Next Location") { model.cyclePlace() }.keyboardShortcut("l")
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(model: model) { NSApp.keyWindow?.close() }
                .frame(width: 540, height: 720)
        }
        #endif
    }
}

private struct ContentView: View {
    @ObservedObject var model: LiveAirspaceModel
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            LiveAirspaceView(model: model, ambient: false, controlsInset: ControlBar.reservedHeight)
            ControlBar(model: model) {
                #if os(macOS)
                openSettings()
                #else
                showSettings = true
                #endif
            }
            .padding(.bottom, 12)
        }
        #if !os(macOS)
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model) { showSettings = false }
        }
        #endif
        #if os(iOS)
        // Don't poll the feeds while the app is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.store.start() } else if phase == .background { model.store.stop() }
        }
        .onChange(of: model.settings.data.display.keepAwake, initial: true) { _, keep in
            UIApplication.shared.isIdleTimerDisabled = keep
        }
        #endif
    }
}
