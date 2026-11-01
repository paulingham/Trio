import SwiftUI

/// The complications Trio offers on the watch face.
///
/// Compiled into the complication extension (which renders them inside WidgetKit),
/// the watch app and the iOS app (which renders them as previews on the settings page).
/// Nothing in this file may use WidgetKit so the same views work in all three.
enum ComplicationKind: String, CaseIterable, Identifiable {
    case glucose
    case gauge
    case iob
    case chart

    var id: String { rawValue }

    /// WidgetKit `kind` string, used for `reloadTimelines(ofKind:)`.
    var widgetKind: String {
        switch self {
        case .glucose: return "TrioGlucoseComplication"
        case .gauge: return "TrioGaugeComplication"
        case .iob: return "TrioIobComplication"
        case .chart: return "TrioChartComplication"
        }
    }

    /// Name shown in the watch face editor and on the iOS settings page.
    var displayName: String {
        switch self {
        case .glucose: return String(localized: "Trio Glucose", comment: "Name of the glucose watch complication")
        case .gauge: return String(localized: "Trio Gauge", comment: "Name of the glucose ring watch complication")
        case .iob: return String(localized: "Trio IOB", comment: "Name of the insulin on board watch complication")
        case .chart: return String(localized: "Trio Chart", comment: "Name of the glucose chart watch complication")
        }
    }

    /// One-line description shown in the watch face editor and under the preview on the iOS settings page.
    var summary: String {
        switch self {
        case .glucose:
            return String(
                localized: "Glucose and trend. Small Line sits under the glucose on circular slots, Corner Label on corners.",
                comment: "Description of the glucose watch complication"
            )
        case .gauge:
            return String(
                localized: "Glucose inside a ring that fills from low to high. Rectangular slots add Small Line, IOB and COB.",
                comment: "Description of the glucose ring watch complication"
            )
        case .iob:
            return String(
                localized: "Insulin on board first, with COB and glucose alongside. Fixed layout; only Grey Out After applies.",
                comment: "Description of the insulin on board watch complication"
            )
        case .chart:
            return String(
                localized: "Glucose, the Small Line and IOB next to the last three hours of readings. Rectangular slots only.",
                comment: "Description of the glucose chart watch complication"
            )
        }
    }

    /// Slots each complication is offered in. The chart needs width so it is rectangular only.
    var slots: [ComplicationSlot] {
        switch self {
        case .chart: return [.rectangular]
        case .gauge: return [.corner, .circular, .rectangular]
        case .glucose,
             .iob: return [.corner, .circular, .rectangular, .inline]
        }
    }
}

enum ComplicationSlot {
    case corner
    case circular
    case rectangular
    case inline
}

/// Everything a complication view needs, worked out once.
struct ComplicationModel {
    let kind: ComplicationKind
    let state: ComplicationState
    let isStale: Bool
    let isPlaceholder: Bool
    let referenceDate: Date
    /// False on accented / vibrant faces where watchOS applies its own tint.
    let fullColor: Bool

    init(
        kind: ComplicationKind,
        state: ComplicationState,
        referenceDate: Date,
        isPlaceholder: Bool = false,
        fullColor: Bool = true
    ) {
        self.kind = kind
        self.state = state
        self.referenceDate = referenceDate
        self.isPlaceholder = isPlaceholder
        self.fullColor = fullColor
        isStale = !isPlaceholder && state.isStale(at: referenceDate)
    }

    /// Colour for the glucose value: the phone's colour on full-colour faces, grey when stale.
    var glucoseColor: Color {
        if isStale { return .gray }
        return fullColor ? state.glucoseColor : .primary
    }

    /// Colour for other primary values such as IOB.
    var valueColor: Color { isStale ? .gray : .primary }

    /// Colour for secondary text.
    var dimColor: Color { isStale ? .gray : .secondary }

    var trendArrow: String { isStale ? "" : state.trendArrow }

    var glucoseWithArrow: String {
        trendArrow.isEmpty ? state.glucose : "\(state.glucose)\(trendArrow)"
    }

    var ageText: String {
        if isPlaceholder { return "-- min" }
        return "\(state.minutesAgo(at: referenceDate)) min"
    }

    var iobText: String { "\(state.iob) U" }
    var cobText: String { "\(state.cob) g" }

    /// Text under the glucose on circular slots (Small Line).
    var secondaryText: String {
        isStale ? ageText : state.text(for: state.secondaryValue, labelled: false)
    }

    /// Curved text on corner slots (Corner Label).
    var cornerText: String {
        isStale ? ageText : state.text(for: state.cornerValue, labelled: true)
    }

    var gaugeValue: Double { state.gaugeValue ?? state.gaugeRange.lowerBound }

    /// Red for lows, green through the middle, amber then red for highs.
    var gaugeGradient: Gradient {
        if isStale || !fullColor {
            return Gradient(colors: [.gray, .gray])
        }
        return Gradient(stops: [
            .init(color: .red, location: 0.0),
            .init(color: .green, location: 0.12),
            .init(color: .green, location: 0.45),
            .init(color: .yellow, location: 0.6),
            .init(color: .orange, location: 0.8),
            .init(color: .red, location: 1.0)
        ])
    }
}

// MARK: - Shared pieces

/// The glucose ring used on circular slots and inside the rectangular gauge.
private struct GlucoseRingGauge: View {
    let model: ComplicationModel
    let fontSize: CGFloat

    var body: some View {
        Gauge(value: model.gaugeValue, in: model.state.gaugeRange) {
            Text("BG")
        } currentValueLabel: {
            Text(model.state.glucose)
                .font(.system(size: fontSize, weight: .bold))
                .minimumScaleFactor(0.5)
                .foregroundStyle(model.glucoseColor)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(model.gaugeGradient)
    }
}

/// Small caption above a value, used for IOB and COB.
private struct LabelledValue: View {
    let model: ComplicationModel
    let label: String
    let value: String
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(model.dimColor)
            Text(value)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(model.valueColor)
        }
    }
}

// MARK: - Circular

struct ComplicationCircularContent: View {
    let model: ComplicationModel

    var body: some View {
        Group {
            switch model.kind {
            case .chart,
                 .glucose:
                glucose
            case .gauge:
                GlucoseRingGauge(model: model, fontSize: 16)
            case .iob:
                iob
            }
        }
        .fontDesign(.rounded)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var glucose: some View {
        VStack(spacing: -2) {
            Text(model.state.glucose)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(model.glucoseColor)
            Text(model.secondaryText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.dimColor)
        }
        .padding(.horizontal, 2)
    }

    private var iob: some View {
        VStack(spacing: -1) {
            Text("IOB")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(model.dimColor)
            Text(model.state.iob)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(model.valueColor)
            Text(model.isStale ? model.ageText : "COB \(model.state.cob)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(model.dimColor)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Corner

/// The large text in the corner itself. The curved label is `ComplicationCornerLabel`.
struct ComplicationCornerMain: View {
    let model: ComplicationModel

    var body: some View {
        Text(model.kind == .iob ? model.state.iob : model.glucoseWithArrow)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(model.kind == .iob ? model.valueColor : model.glucoseColor)
    }
}

/// Content for the curved corner label. WidgetKit bends text and gauges round the corner.
struct ComplicationCornerLabel: View {
    let model: ComplicationModel

    var body: some View {
        switch model.kind {
        case .gauge:
            Gauge(value: model.gaugeValue, in: model.state.gaugeRange) {
                Text("BG")
            } currentValueLabel: {
                Text(model.state.glucose)
            } minimumValueLabel: {
                Text(model.state.gaugeRange.lowerBound, format: .number.precision(.fractionLength(0)))
            } maximumValueLabel: {
                Text(model.state.gaugeRange.upperBound, format: .number.precision(.fractionLength(0)))
            }
            .tint(model.gaugeGradient)
        case .iob:
            Text(model.isStale ? model.ageText : "COB \(model.cobText) · \(model.state.glucose)")
        default:
            Text(model.cornerText)
        }
    }
}

// MARK: - Rectangular

struct ComplicationRectangularContent: View {
    let model: ComplicationModel

    var body: some View {
        Group {
            switch model.kind {
            case .glucose:
                glucose
            case .gauge:
                gauge
            case .iob:
                iob
            case .chart:
                chart
            }
        }
        .fontDesign(.rounded)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var glucoseLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.state.glucose)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(model.glucoseColor)
            if !model.isStale {
                Text(model.state.trendArrow)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.glucoseColor)
                Text(model.state.delta)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ageLine: some View {
        Text("\(model.ageText) ago · loop \(model.state.lastLoopTime)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private var glucose: some View {
        VStack(alignment: .leading, spacing: 1) {
            glucoseLine
            Text("IOB \(model.iobText) · COB \(model.cobText)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(model.valueColor)
            ageLine
        }
    }

    private var gauge: some View {
        HStack(spacing: 8) {
            GlucoseRingGauge(model: model, fontSize: 14)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.secondaryText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.valueColor)
                Text("IOB \(model.iobText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.valueColor)
                Text("COB \(model.cobText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.dimColor)
            }
            Spacer(minLength: 0)
        }
    }

    private var iob: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                LabelledValue(model: model, label: "IOB", value: model.iobText, size: 22)
                LabelledValue(model: model, label: "COB", value: model.cobText, size: 22)
            }
            HStack(spacing: 4) {
                Text(model.glucoseWithArrow)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(model.glucoseColor)
                Text(model.isStale ? "\(model.ageText) ago" : "\(model.state.delta) · loop \(model.state.lastLoopTime)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.glucoseWithArrow)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(model.glucoseColor)
                Text(model.secondaryText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.dimColor)
                // Third line is IOB unless Small Line already shows it, then COB.
                Text(model.state.secondaryValue == .iob ? "COB \(model.state.cob)" : "IOB \(model.state.iob)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.valueColor)
            }
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: true, vertical: false)
            ComplicationSparkline(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Inline

struct ComplicationInlineContent: View {
    let model: ComplicationModel

    var body: some View {
        Text(text)
    }

    private var text: String {
        switch model.kind {
        case .iob:
            return model.isStale
                ? "IOB \(model.iobText) · \(model.ageText) ago"
                : "IOB \(model.iobText) · COB \(model.cobText) · \(model.glucoseWithArrow)"
        default:
            return model.isStale
                ? "\(model.state.glucose) · \(model.ageText) ago"
                : "\(model.glucoseWithArrow) \(model.state.delta) · IOB \(model.state.iob)"
        }
    }
}

// MARK: - Sparkline

/// Last three hours of glucose as a line, plus the current reading as a dot.
/// Plain `Path` drawing so it works in a widget without Swift Charts.
struct ComplicationSparkline: View {
    let model: ComplicationModel

    /// Vertical range: the data plus the in-range band, stretched to at least the minimum span.
    private var valueRange: ClosedRange<Double> {
        let values = model.state.history.map(\.v)
        let band = model.state.chartBand
        let lo = min(values.min() ?? band.lowerBound, band.lowerBound)
        let hi = max(values.max() ?? band.upperBound, band.upperBound)
        return lo ... max(hi, lo + model.state.chartMinimumSpan)
    }

    var body: some View {
        let points = model.state.history
        let range = valueRange
        let end = model.state.date.timeIntervalSince1970
        let start = end - ComplicationState.chartWindow
        let band = model.state.chartBand

        GeometryReader { geo in
            if points.count >= 2 {
                let size = geo.size
                let inset: CGFloat = 3
                let x: (TimeInterval) -> CGFloat = { t in
                    inset + CGFloat((t - start) / (end - start)) * (size.width - inset * 2)
                }
                let y: (Double) -> CGFloat = { v in
                    let fraction = (v - range.lowerBound) / (range.upperBound - range.lowerBound)
                    return inset + CGFloat(1 - fraction) * (size.height - inset * 2)
                }
                let bandTop = y(band.upperBound)
                let bandBottom = y(band.lowerBound)

                Rectangle()
                    .fill(Color.primary.opacity(model.fullColor ? 0.12 : 0.2))
                    .frame(width: size.width, height: max(1, bandBottom - bandTop))
                    .position(x: size.width / 2, y: (bandTop + bandBottom) / 2)

                Path { path in
                    for (index, point) in points.enumerated() {
                        let p = CGPoint(x: x(point.t), y: y(point.v))
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                .stroke(model.glucoseColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(model.glucoseColor)
                        .frame(width: 4, height: 4)
                        .position(x: x(last.t), y: y(last.v))
                }
            } else {
                Text("no data")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - Preview (settings page)

/// Mock of a watch face slot, used on the iOS settings page so the user can see
/// each complication with their current configuration. Not used inside WidgetKit.
struct ComplicationPreview: View {
    let kind: ComplicationKind
    let slot: ComplicationSlot
    let state: ComplicationState

    var body: some View {
        let model = ComplicationModel(kind: kind, state: state, referenceDate: state.date)
        switch slot {
        case .circular:
            ZStack {
                Circle().fill(Color.white.opacity(0.14))
                ComplicationCircularContent(model: model)
                    .padding(4)
            }
            .frame(width: 66, height: 66)
        case .rectangular:
            ComplicationRectangularContent(model: model)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 172, height: 66)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.14)))
        case .corner:
            // Straight-line stand-in for the curved corner: main text with the label beneath.
            VStack(spacing: 2) {
                ComplicationCornerMain(model: model)
                if kind == .gauge {
                    Gauge(value: model.gaugeValue, in: state.gaugeRange) { EmptyView() }
                        .gaugeStyle(.accessoryLinear)
                        .tint(model.gaugeGradient)
                        .frame(width: 56)
                } else {
                    ComplicationCornerLabel(model: model)
                        .font(.system(size: 9, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .padding(6)
            .frame(width: 80, height: 66)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.14)))
        case .inline:
            ComplicationInlineContent(model: model)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
