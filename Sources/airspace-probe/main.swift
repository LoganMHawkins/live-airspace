import Foundation
import LiveAirspaceKit

// Fetches every source once for the default airspace and prints how well they agree.
// `--place "London LHR"` picks one of the airport presets instead of the default.
var config = AirspaceConfig.default
if let i = CommandLine.arguments.firstIndex(of: "--place"), i + 1 < CommandLine.arguments.count,
   let p = AirspaceConfig.presets.first(where: { $0.name == CommandLine.arguments[i + 1] }) { config = p }
// Optional OpenSky sign-in for the probe: OPENSKY_CLIENT_ID / OPENSKY_CLIENT_SECRET in the environment.
let env = ProcessInfo.processInfo.environment
let credentials = env["OPENSKY_CLIENT_ID"].flatMap { id in env["OPENSKY_CLIENT_SECRET"].map { OpenSkyCredentials(clientID: id, clientSecret: $0) } }
let sources = AirspaceStore.defaultSources(openSky: credentials)
let now = Date()

var reports: [SourceReport] = []
for source in sources {
    do {
        let r = try await source.fetch(center: config.center, radiusNM: config.radiusNM, now: now)
        print("\(source.id.rawValue): \(r.count) aircraft")
        reports += r
    } catch {
        print("\(source.id.rawValue): FAILED \(error)")
    }
}

let merged = AirspaceMerger().merge(reports, now: now)
let multi = merged.filter { $0.sources.count > 1 }
let confirmed = multi.filter { !$0.agreement.isDisputed }
let disputed = multi.filter { $0.agreement.isDisputed }
let altDisputed = merged.filter(\.altitudeDisputed)

print("\nmerged: \(merged.count) aircraft, \(multi.count) seen by 2+ sources")
print("  position confirmed: \(confirmed.count), disputed: \(disputed.count), altitude disputed: \(altDisputed.count)")
for ac in merged.sorted(by: { $0.sources.count > $1.sources.count }).prefix(12) {
    let alt = ac.altitudeFt.map { "\(Int($0)) ft" } ?? "—"
    print("  \(ac.displayName.padding(toLength: 9, withPad: " ", startingAt: 0)) \((ac.typeCode ?? "—").padding(toLength: 5, withPad: " ", startingAt: 0)) \(alt.padding(toLength: 9, withPad: " ", startingAt: 0)) \(ac.sources.map(\.rawValue).joined(separator: "+")) \(ac.agreement)")
}

// `airspace-probe --snapshot out.png` renders the live view to an image after letting the store poll for a few seconds.
#if canImport(AppKit)
import AppKit
import SwiftUI
import LiveAirspaceUI

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    let model = await MainActor.run { () -> LiveAirspaceModel in
        let m = LiveAirspaceModel(defaults: UserDefaults(suiteName: "airspace-probe") ?? .standard, allowsLocation: false)
        m.settings.data.place = .preset(config.name)
        m.settings.data.display.mapOpacity = 0
        m.store.start()
        return m
    }
    try? await Task.sleep(for: .seconds(14))
    await MainActor.run {
        let view = LiveAirspaceView(model: model, ambient: false).frame(width: 1920, height: 1080)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } else {
            print("render failed")
        }
    }
}
#endif
