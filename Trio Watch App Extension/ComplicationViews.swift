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

    var displayName: String {
        switch self {
        case .glucose: return "Trio Glucose"
        case .gauge: return "Trio Gauge"
        case .iob: return "Trio IOB"
        case .chart: return "Trio Chart"
        }
    }

    var summary: String {
        switch self {
        case .glucose: return "Glucose and trend. Small Line under it on circular slots, Corner Label on corner slots."
        case .gauge: return "Glucose inside a ring that fills from low to high. Corner slots curve the ring round the glucose."
        case .iob: return "Insulin on board first, with COB and glucose alongside."
        case .chart: return "Glucose, delta and IOB next to the last three hours of readings. Rectangular slots only."
        }
    }

    /// Slots each complication is offered in. The chart needs width so it is rectangular only.
    var slots: [ComplicationSlot] {
        switch self {
        case .chart: return [.rectangular]
        case .gauge: return [.corner, .circular, .rectangular]
        case .glucose, .iob: return [.corner, .circular, .rectangular, .inline]
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
        referenceDate: Date = Date(),
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

    var glucoseColor: Color {
        if isStale { return .gray }
        return fullColor ? state.glucoseColor : .primary
    }

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

    /// Text under the glucose on circular slots.
    var secondaryText: String {
        isStale ? ageText : state.text(for: state.resolvedSecondaryValue, labelled: false)
    }

    /// Curved text on corner slots.
    var cornerText: String {
        isStale ? ageText : state.text(for: state.resolvedCornerValue, labelled: true)
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

    /// Readings inside the chart window, oldest first.
    var chartPoints: [ComplicationPoint] {
        let from = state.date.timeIntervalSince1970 - ComplicationState.chartWindow
        return (state.history ?? []).filter { $0.t >= from }.sorted { $0.t < $1.t }
    }
}

// MARK: - Circular

struct ComplicationCircularContent: View {
    let model: ComplicationModel

    var body: some View {
        switch model.kind {
        case .glucose, .chart:
            glucose
        case .gauge:
            gauge
        case .iob:
            iob
        }
    }

    private var glucose: some View {
        VStack(spacing: -2) {
            Text(model.state.glucose)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(model.glucoseColor)
            Text(model.secondaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(model.dimColor)
        }
        .padding(.horizontal, 2)
    }

    private var gauge: some View {
        Gauge(value: model.gaugeValue, in: model.state.gaugeRange) {
            Text("BG")
        } currentValueLabel: {
            Text(model.state.glucose)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(model.glucoseColor)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(model.gaugeGradient)
    }

    private var iob: some View {
        VStack(spacing: -1) {
            Text("IOB")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(model.dimColor)
            Text(model.state.iob)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(model.isStale ? .gray : .primary)
            Text(model.isStale ? model.ageText : "COB \(model.state.cob)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
        switch model.kind {
        case .iob:
            Text(model.state.iob)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(model.isStale ? .gray : .primary)
        default:
            Text(model.glucoseWithArrow)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(model.glucoseColor)
        }
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
                Text(model.state.isMmol ? "3" : "50")
            } maximumValueLabel: {
                Text(model.state.isMmol ? "16" : "290")
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

    private var glucoseLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.state.glucose)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(model.glucoseColor)
            if !model.isStale {
                Text(model.state.trendArrow)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.glucoseColor)
                Text(model.state.delta)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }

    private var ageLine: some View {
        Text("\(model.ageText) ago · loop \(model.state.lastLoopTime)")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var glucose: some View {
        VStack(alignment: .leading, spacing: 1) {
            glucoseLine
            Text("IOB \(model.iobText) · COB \(model.cobText)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(model.isStale ? .gray : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ageLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gauge: some View {
        HStack(spacing: 8) {
            Gauge(value: model.gaugeValue, in: model.state.gaugeRange) {
                Text("BG")
            } currentValueLabel: {
                Text(model.state.glucose)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(model.glucoseColor)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(model.gaugeGradient)
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(model.trendArrow)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(model.glucoseColor)
                    Text(model.isStale ? model.ageText : model.state.delta)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.isStale ? .gray : .primary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text("IOB \(model.iobText)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(model.isStale ? .gray : .primary)
                    .lineLimit(1)
                Text("COB \(model.cobText)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(model.dimColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iob: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("IOB")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.dimColor)
                    Text(model.iobText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(model.isStale ? .gray : .primary)
                }
                VStack(alignment: .leading, spacing: -2) {
                    Text("COB")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.dimColor)
                    Text(model.cobText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(model.isStale ? .gray : .primary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Text(model.glucoseWithArrow)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(model.glucoseColor)
                Text(model.isStale ? "\(model.ageText) ago" : "\(model.state.delta) · loop \(model.state.lastLoopTime)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.glucoseWithArrow)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(model.glucoseColor)
                Text(model.isStale ? model.ageText : model.state.delta)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(model.dimColor)
                Text("IOB \(model.state.iob)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(model.isStale ? .gray : .primary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: true, vertical: false)
            ComplicationSparkline(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        GeometryReader { geo in
            let points = model.chartPoints
            let size = geo.size
            let lineColor: Color = model.isStale ? .gray : (model.fullColor ? model.glucoseColor : .primary)

            if points.count >= 2 {
                let end = model.state.date.timeIntervalSince1970
                let start = end - ComplicationState.chartWindow
                let values = points.map(\.v)
                // Keep the in-range band in view so a flat line sits where it should.
                let floorValue = model.state.isMmol ? 3.5 : 63.0
                let ceilValue = model.state.isMmol ? 10.0 : 180.0
                let lo = min(values.min() ?? floorValue, floorValue)
                let hi = max(values.max() ?? ceilValue, ceilValue)
                let span = max(hi - lo, model.state.isMmol ? 1 : 18)
                let inset: CGFloat = 3

                let x: (TimeInterval) -> CGFloat = { t in
                    inset + CGFloat((t - start) / (end - start)) * (size.width - inset * 2)
                }
                let y: (Double) -> CGFloat = { v in
                    inset + CGFloat(1 - (v - lo) / span) * (size.height - inset * 2)
                }

                // Faint band marking the in-range zone.
                let bandTop = y(ceilValue)
                let bandBottom = y(floorValue)
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
                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(lineColor)
                        .frame(width: 4, height: 4)
                        .position(x: x(last.t), y: y(last.v))
                }
            } else {
                Text("no data")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size.width, height: size.height)
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

    private var model: ComplicationModel {
        ComplicationModel(kind: kind, state: state, referenceDate: state.date, isPlaceholder: false, fullColor: true)
    }

    var body: some View {
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
            VStack(spacing: 0) {
                ComplicationCornerMain(model: model)
                ComplicationCornerLabel(model: model)
                    .font(.system(size: 9, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
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
