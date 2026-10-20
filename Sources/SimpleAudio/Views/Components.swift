import SwiftUI

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    init<V: View>(_ title: String, @ViewBuilder trailing: () -> V) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color(nsColor: Theme.textDim))
                .tracking(0.6)
                .textCase(.uppercase)
            Spacer()
            if let trailing {
                trailing
            }
        }
        .padding(.bottom, 2)
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Color(nsColor: Theme.textDim))
                .frame(width: 78, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

struct NumberField: View {
    let value: Double
    var unit: String = "s"
    var step: Double = 0.05
    var range: ClosedRange<Double> = 0...36000
    var decimals: Int = 2
    let onCommit: (Double) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(
        value: Double,
        unit: String = "s",
        step: Double = 0.05,
        range: ClosedRange<Double> = 0...36000,
        decimals: Int = 2,
        onCommit: @escaping (Double) -> Void
    ) {
        self.value = value
        self.unit = unit
        self.step = step
        self.range = range
        self.decimals = decimals
        self.onCommit = onCommit
        self._text = State(initialValue: String(format: "%.\(decimals)f", value))
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.text))
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onAppear { sync() }
                .onChange(of: value) { _, _ in
                    if !focused { sync() }
                }
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textFaint))
            }
            VStack(spacing: 1) {
                Button {
                    onCommit(min(max(value + step, range.lowerBound), range.upperBound))
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 12, height: 8)
                }
                .buttonStyle(.plain)
                Button {
                    onCommit(min(max(value - step, range.lowerBound), range.upperBound))
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 12, height: 8)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Color(nsColor: Theme.textDim))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(focused ? 0.25 : 0.08), lineWidth: 1)
                )
        )
    }

    private func sync() {
        text = String(format: "%.\(decimals)f", value)
    }

    private func commit() {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(normalized), parsed.isFinite {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            onCommit(clamped)
            text = String(format: "%.\(decimals)f", clamped)
        } else {
            sync()
        }
    }
}

struct CommitField: View {
    let value: String
    var placeholder: String = ""
    let onCommit: (String) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(value: String, placeholder: String = "", onCommit: @escaping (String) -> Void) {
        self.value = value
        self.placeholder = placeholder
        self.onCommit = onCommit
        self._text = State(initialValue: value)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(Color(nsColor: Theme.text))
            .focused($focused)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(focused ? 0.25 : 0.08), lineWidth: 1)
                    )
            )
            .onAppear { text = value }
            .onChange(of: value) { _, newVal in
                if !focused { text = newVal }
            }
            .onSubmit {
                onCommit(text)
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused && text != value {
                    onCommit(text)
                }
            }
    }
}

struct IconButton: View {
    let symbol: String
    var helpText: String = ""
    var active: Bool = false
    var tint: Color = Color(nsColor: Theme.accent)
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    disabled
                        ? Color(nsColor: Theme.textFaint)
                        : (active ? Color(nsColor: Theme.background) : Color(nsColor: Theme.text))
                )
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? tint : Color.white.opacity(disabled ? 0.02 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(helpText)
    }
}

struct TextButton: View {
    let title: String
    var symbol: String? = nil
    var prominent: Bool = false
    var compact: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: compact ? 10.5 : 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: compact ? 11 : 11.5, weight: prominent ? .semibold : .medium))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                disabled
                    ? Color(nsColor: Theme.textFaint)
                    : (prominent ? Color(nsColor: Theme.background) : Color(nsColor: Theme.text))
            )
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        prominent
                            ? Color(nsColor: Theme.accent).opacity(disabled ? 0.35 : 1.0)
                            : Color.white.opacity(disabled ? 0.02 : 0.07)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Compact real-time stereo L/R peak level meter (`0.0 ... 1.0` linear peak mapped to `-48 ... 0 dBFS`).
struct StereoMeterView: View {
    let peakLeft: Float
    let peakRight: Float

    private func normalized(_ linear: Float) -> CGFloat {
        guard linear > 0.0001 else { return 0 }
        let db = 20.0 * log10(Double(linear))
        return CGFloat(min(max((db + 48.0) / 48.0, 0), 1))
    }

    var body: some View {
        VStack(spacing: 3) {
            meterBar(level: normalized(peakLeft), raw: peakLeft)
            meterBar(level: normalized(peakRight), raw: peakRight)
        }
        .frame(width: 76, height: 13)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func meterBar(level: CGFloat, raw: Float) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(raw: raw))
                    .frame(width: max(0, geo.size.width * level))
            }
        }
        .frame(height: 4)
    }

    private func barColor(raw: Float) -> Color {
        if raw >= 0.98 { return Color(nsColor: Theme.meterHot) }
        if raw >= 0.70 { return Color(nsColor: Theme.meterWarm) }
        return Color(nsColor: Theme.meterSafe)
    }
}
