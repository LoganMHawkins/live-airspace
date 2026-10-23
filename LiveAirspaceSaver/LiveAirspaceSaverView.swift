import ScreenSaver
import SwiftUI
import LiveAirspaceKit
import LiveAirspaceUI

/// macOS screen saver hosting the shared SwiftUI radar view.
@objc(LiveAirspaceSaverView)
final class LiveAirspaceSaverView: ScreenSaverView {
    private var model: LiveAirspaceModel?
    private var configureWindow: NSWindow?

    private static var moduleDefaults: UserDefaults {
        ScreenSaverDefaults(forModuleWithName: Bundle(for: LiveAirspaceSaverView.self).bundleIdentifier ?? "com.bureau.liveairspace.saver") ?? .standard
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true
        let model = MainActor.assumeIsolated { LiveAirspaceModel(defaults: Self.moduleDefaults, allowsLocation: false) }
        self.model = model
        let host = MainActor.assumeIsolated { NSHostingView(rootView: LiveAirspaceView(model: model, ambient: true)) }
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        guard let model else { return nil }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = MainActor.assumeIsolated {
            NSHostingView(rootView: SettingsView(model: model, allowsNearMe: false) { [weak window] in
                guard let window, let parent = window.sheetParent else { return }
                parent.endSheet(window)
            })
        }
        configureWindow = window
        return window
    }
}
