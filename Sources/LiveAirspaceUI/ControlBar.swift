#if !os(tvOS)
import SwiftUI

/// Floating controls for touch and mouse (the Apple TV uses the remote instead).
public struct ControlBar: View {
    @ObservedObject var model: LiveAirspaceModel
    var onSettings: () -> Void

    /// Height the radar view should reserve at the bottom so its cards and legend sit above the bar.
    public static let reservedHeight: CGFloat = 76

    public init(model: LiveAirspaceModel, onSettings: @escaping () -> Void) {
        self.model = model
        self.onSettings = onSettings
    }

    public var body: some View {
        HStack(spacing: 4) {
            button("chevron.left", "Previous aircraft") { model.store.cycleSelection(-1) }
            button("chevron.right", "Next aircraft") { model.store.cycleSelection(1) }
            divider
            button("minus.magnifyingglass", "Zoom out") { model.zoom(in: false) }
            button("plus.magnifyingglass", "Zoom in") { model.zoom(in: true) }
            divider
            button("location", "Change location") { model.cyclePlace() }
            button("gearshape", "Settings", action: onSettings)
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
