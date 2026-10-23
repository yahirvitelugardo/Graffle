import SwiftUI

// Shared building blocks for the Format and Arrange tabs.

/// A titled card of rows.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(Tok.textSecondary))
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Tok.Radius.card).fill(Color(Tok.cardBG)))
                .overlay(RoundedRectangle(cornerRadius: Tok.Radius.card).stroke(Color(Tok.cardOutline), lineWidth: 0.5))
        }
    }
}

/// A label on the left, a control on the right, at least 44pt tall.
struct InspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 14)).foregroundStyle(Color(Tok.textPrimary))
            Spacer(minLength: 4)
            content
        }
        .frame(minHeight: 44)
    }
}

/// A slider with a title and a readout.
struct InspectorSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var decimals = 0
    var suffix = ""
    var displayScale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14)).foregroundStyle(Color(Tok.textPrimary))
                Spacer()
                Text(String(format: "%.\(decimals)f", value * displayScale) + suffix)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Color(Tok.textSecondary))
            }
            Slider(value: $value, in: range).frame(minHeight: 44)
        }
    }
}

/// A number field that commits when editing ends.
struct InspectorNumber: View {
    let title: String
    @Binding var value: Double
    var suffix = ""
    var decimals = 2
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(Color(Tok.textSecondary))
            HStack(spacing: 4) {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...decimals)))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.leading)
                    .disabled(disabled)
                if !suffix.isEmpty { Text(suffix).font(.system(size: 12)).foregroundStyle(Color(Tok.textSecondary)) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: Tok.Radius.field).fill(Color(Tok.fieldBG)))
            .opacity(disabled ? 0.5 : 1)
        }
    }
}

/// A prominent-when-enabled action button, at least 44pt tall.
struct InspectorButton: View {
    let title: String
    var symbol: String? = nil
    var enabled = true
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15)) }
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(destructive ? Color.red : Color(Tok.textPrimary))
            .background(RoundedRectangle(cornerRadius: Tok.Radius.field).fill(Color(Tok.fieldBG)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Equal-width icon-only button grid row.
struct InspectorIconButton: View {
    let symbol: String
    let label: String
    var enabled = true
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? Color(Tok.onAccent) : Color(Tok.iconDefault))
                .background(RoundedRectangle(cornerRadius: Tok.Radius.field).fill(selected ? Color(Tok.accent) : Color(Tok.fieldBG)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

/// SwiftUI color <-> RGBA.
func inspectorColor(_ get: @escaping () -> RGBA, _ set: @escaping (RGBA) -> Void) -> Binding<Color> {
    Binding(get: { Color(uiColor: get().ns) }, set: { set(RGBA(UIColor($0))) })
}

/// The ready-made palette from the Mac's ColorPresetsView.
struct InspectorPresets: View {
    let selected: RGBA?
    let onPick: (RGBA) -> Void

    private static func hex(_ v: UInt32) -> RGBA {
        RGBA(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }
    static let colors: [RGBA] = ([0x000000, 0x2B2B2B, 0x565656, 0x8D8D8D, 0xC3C3C3, 0xFFFFFF,
                                  0x0014FF, 0xF52B1B, 0xEB3CFF, 0x55FF33, 0x40F5F5, 0xFFFF1A,
                                  0x7580FF, 0xF37D78, 0xF188F5, 0x8FEE7C, 0x8CF5F5, 0xFAF28A,
                                  0xBBBFFF, 0xF8B8B4, 0xF5BDF8, 0xBAF5AD, 0xBEFAFA, 0xFFFFBF] as [UInt32]).map(hex)

    private func matches(_ c: RGBA) -> Bool {
        guard let s = selected else { return false }
        return abs(s.r - c.r) < 0.004 && abs(s.g - c.g) < 0.004 && abs(s.b - c.b) < 0.004
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(Array(Self.colors.enumerated()), id: \.offset) { _, c in
                Button { onPick(c) } label: {
                    RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: c.ns))
                        .frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(matches(c) ? Color(Tok.accent) : Color(Tok.divider), lineWidth: matches(c) ? 2.5 : 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preset color")
            }
        }
    }
}

extension Binding {
    /// A binding whose setter runs `then` after storing.
    func onSet(_ then: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; then($0) })
    }
}
