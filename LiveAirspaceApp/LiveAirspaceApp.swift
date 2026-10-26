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
                Button("Search…") { model.searchRequested = true }.keyboardShortcut("f")
                Divider()
                Button("Next Aircraft") { model.store.cycleSelection(1) }.keyboardShortcut("]")
                Button("Previous Aircraft") { model.store.cycleSelection(-1) }.keyboardShortcut("[")
                Button("Follow Selected Aircraft") { if let id = model.store.focus?.id { model.follow(id) } }.keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
                Button("Zoom In") { model.zoom(in: true) }.keyboardShortcut("=")
                Button("Zoom Out") { model.zoom(in: false) }.keyboardShortcut("-")
                Button("Home View") { model.recenter() }.keyboardShortcut("0")
                Button("Save This View") { model.saveCurrentView() }.keyboardShortcut("d")
                Divider()
                Button("Next Location") { model.cyclePlace() }.keyboardShortcut("l")
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(model: model, onShowWelcome: { NSApp.keyWindow?.close(); model.showWelcomeAgain() }) { NSApp.keyWindow?.close() }
                .frame(width: 560, height: 760)
        }
        #endif
    }
}

private enum Sheet: Identifiable {
    case search, settings
    var id: Self { self }
}

private struct ContentView: View {
    @ObservedObject var model: LiveAirspaceModel
    @ObservedObject var settings: AppSettings
    @State private var sheet: Sheet?
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    init(model: LiveAirspaceModel) {
        self.model = model
        self.settings = model.settings
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LiveAirspaceView(model: model, ambient: false, controlsInset: ControlBar.reservedHeight)
            ControlBar(model: model, onSearch: { sheet = .search }, onSettings: openSettingsUI, onWelcome: showWelcome)
                .padding(.bottom, 12)
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .search:
                SearchView(model: model) { sheet = nil }
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    #endif
            case .settings:
                SettingsView(model: model, onShowWelcome: {
                    sheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.showWelcomeAgain() }
                }) { sheet = nil }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(get: { !settings.data.hasSeenWelcome }, set: { _ in })) {
            WelcomeView(model: model) {}
        }
        #else
        .sheet(isPresented: Binding(get: { !settings.data.hasSeenWelcome }, set: { _ in })) {
            WelcomeView(model: model) {}
                .interactiveDismissDisabled()
        }
        #endif
        .onChange(of: model.searchRequested) { _, requested in
            if requested { sheet = .search; model.searchRequested = false }
        }
        #if os(iOS)
        // Don't poll the feeds while the app is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.store.start() } else if phase == .background { model.store.stop() }
        }
        .onChange(of: settings.data.display.keepAwake, initial: true) { _, keep in
            UIApplication.shared.isIdleTimerDisabled = keep
        }
        #endif
    }

    private func openSettingsUI() {
        #if os(macOS)
        openSettings()
        #else
        sheet = .settings
        #endif
    }

    private func showWelcome() {
        model.showWelcomeAgain()
    }
}
