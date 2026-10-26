import SwiftUI

/// Shared look for the screens around the radar (Welcome, Search, Settings). The radar itself is always dark, so these are too.
enum Theme {
    static let background = Color(red: 0.012, green: 0.022, blue: 0.035)
    static let ink = Color(red: 0.55, green: 0.95, blue: 0.85)
    static let cyan = Color(red: 0.40, green: 0.80, blue: 1.0)
    static let violet = Color(red: 0.75, green: 0.60, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.35)
    static let green = Color(red: 0.45, green: 0.95, blue: 0.70)
    static let red = Color(red: 1.0, green: 0.45, blue: 0.40)

    /// Text on a card: full-strength and a quieter secondary.
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
}

extension View {
    /// Liquid Glass where the system has it, a blurred material elsewhere.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 20) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// A prominent button in the app's accent colour (glass where available).
    @ViewBuilder func accentButton() -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.buttonStyle(.glassProminent).tint(Theme.cyan)
        } else {
            self.buttonStyle(.borderedProminent).tint(Theme.cyan)
        }
    }
}

/// A titled group of settings.
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.ink)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 22)
    }
}

/// A toggle with an icon and an optional explanation underneath.
struct SettingsToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    var detail: String?

    init(_ title: String, symbol: String, isOn: Binding<Bool>, detail: String? = nil) {
        self.title = title
        self.symbol = symbol
        self._isOn = isOn
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                Label(title, systemImage: symbol)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.primary)
            }
            if let detail {
                Text(detail).settingsFootnote()
            }
        }
    }
}

extension Text {
    func settingsFootnote() -> some View {
        self.font(.system(.footnote, design: .rounded))
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A labelled segmented choice.
struct SegmentedChoice<Value: Hashable>: View {
    let title: String
    let symbol: String
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.primary)
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { Text(options[$0].label).tag(options[$0].value) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
