import SwiftUI
import WidgetKit

// MARK: - Glucose complication

/// Timeline entry for the data-driven complication.
struct TrioGlucoseEntry: TimelineEntry {
    let date: Date
    let state: ComplicationState
    /// True when `state` is older than `ComplicationState.staleAfter` at `date`.
    let isStale: Bool
    /// True for the placeholder / preview entry.
    let isPlaceholder: Bool

    init(date: Date, state: ComplicationState, isPlaceholder: Bool = false) {
        self.date = date
        self.state = state
        self.isPlaceholder = isPlaceholder
        isStale = !isPlaceholder && state.isStale(at: date)
    }
}

struct TrioGlucoseProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioGlucoseEntry {
        TrioGlucoseEntry(date: Date(), state: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrioGlucoseEntry) -> Void) {
        if context.isPreview {
            completion(TrioGlucoseEntry(date: Date(), state: Self.preview, isPlaceholder: true))
            return
        }
        completion(TrioGlucoseEntry(date: Date(), state: ComplicationStore.load() ?? .placeholder))
    }

    /// One entry for now and, if the reading is still fresh, a second entry at the moment it
    /// turns stale so the face greys it out without the app having to wake up. `.atEnd` makes
    /// WidgetKit ask again after that; the watch app also calls `reloadAllTimelines()` every time
    /// new data arrives from the phone, which is the normal refresh path.
    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioGlucoseEntry>) -> Void) {
        let now = Date()
        let state = ComplicationStore.load() ?? .placeholder
        var entries = [TrioGlucoseEntry(date: now, state: state)]

        let staleAt = state.date.addingTimeInterval(ComplicationState.staleAfter + 1)
        if staleAt > now {
            entries.append(TrioGlucoseEntry(date: staleAt, state: state))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let preview = ComplicationState(
        date: Date(),
        glucose: "6.4",
        glucoseColorHex: "#4cd964",
        trend: "Flat",
        delta: "+0.1",
        iob: "1.25",
        cob: "12",
        lastLoopTime: "2 min"
    )
}

struct TrioGlucoseEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: TrioGlucoseEntry

    private var state: ComplicationState { entry.state }

    /// Full-colour faces get the phone's glucose colour; accented/vibrant faces are tinted by watchOS.
    private var glucoseColor: Color {
        if entry.isStale { return .gray }
        return renderingMode == .fullColor ? state.glucoseColor : .primary
    }

    private var glucoseWithArrow: String {
        let arrow = entry.isStale ? "" : state.trendArrow
        return arrow.isEmpty ? state.glucose : "\(state.glucose)\(arrow)"
    }

    private var ageText: String {
        if entry.isPlaceholder { return "-- min" }
        return "\(state.minutesAgo(at: entry.date)) min"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        #if os(watchOS)
            case .accessoryCorner:
                corner
        #endif
        default:
            circular
        }
    }

    // Glucose large, arrow and delta small underneath.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(state.glucose)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(glucoseColor)
                    .widgetAccentable()
                Text(entry.isStale ? ageText : "\(state.trendArrow) \(state.delta)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(entry.isStale ? .gray : .secondary)
            }
            .padding(.horizontal, 2)
        }
        .widgetBackground(backgroundView: Color.clear)
    }

    #if os(watchOS)
        // Glucose + arrow in the corner, IOB on the curved label.
        private var corner: some View {
            Text(glucoseWithArrow)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(glucoseColor)
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel {
                    Text(entry.isStale ? ageText : "IOB \(state.iob)")
                }
                .widgetBackground(backgroundView: Color.clear)
        }
    #endif

    // Three lines: glucose/arrow/delta, IOB + COB, age + loop.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(state.glucose)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(glucoseColor)
                    .widgetAccentable()
                if !entry.isStale {
                    Text(state.trendArrow)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(glucoseColor)
                    Text(state.delta)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            Text("IOB \(state.iob) U · COB \(state.cob) g")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(entry.isStale ? .gray : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(ageText) ago · loop \(state.lastLoopTime)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetBackground(backgroundView: Color.clear)
    }

    private var inline: some View {
        Text(entry.isStale
            ? "\(state.glucose) · \(ageText) ago"
            : "\(glucoseWithArrow) \(state.delta) · IOB \(state.iob)")
            .widgetBackground(backgroundView: Color.clear)
    }
}

struct TrioGlucoseComplication: Widget {
    let kind: String = "TrioGlucoseComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrioGlucoseProvider()) { entry in
            TrioGlucoseEntryView(entry: entry)
        }
        .configurationDisplayName("Trio Glucose")
        .description("Current glucose, trend, IOB and COB from Trio")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
            return [.accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
            return [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

// MARK: - App icon launcher (unchanged behaviour)

struct TrioWatchComplicationEntry: TimelineEntry {
    let date: Date
}

struct TrioWatchComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioWatchComplicationEntry {
        TrioWatchComplicationEntry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (TrioWatchComplicationEntry) -> Void) {
        completion(TrioWatchComplicationEntry(date: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioWatchComplicationEntry>) -> Void) {
        completion(Timeline(entries: [TrioWatchComplicationEntry(date: Date())], policy: .never))
    }
}

struct TrioWatchComplicationEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    var entry: TrioWatchComplicationEntry

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            TrioAccessoryCircularView(entry: entry)
        #if os(watchOS)
            case .accessoryCorner:
                TrioAccessoryCornerView(entry: entry)
        #endif
        default:
            Image("ComplicationIcon")
                .widgetAccentable()
                .widgetBackground(backgroundView: Color.clear)
        }
    }
}

#if os(watchOS)
    /// Corner Complication
    struct TrioAccessoryCornerView: View {
        var entry: TrioWatchComplicationProvider.Entry

        var body: some View {
            Text("")
                .widgetCurvesContent()
                .widgetLabel {
                    Text("Trio")
                }
                .widgetBackground(backgroundView: Color.clear)
        }
    }
#endif

/// Circular Complication
struct TrioAccessoryCircularView: View {
    var entry: TrioWatchComplicationProvider.Entry

    var body: some View {
        Image("ComplicationIcon")
            .resizable()
            .widgetAccentable()
            .widgetBackground(backgroundView: Color.clear)
    }
}

struct TrioWatchComplication: Widget {
    let kind: String = "TrioWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrioWatchComplicationProvider()) { entry in
            TrioWatchComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Trio")
        .description("Displays Trio app icon as complication")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
            return [.accessoryCorner, .accessoryCircular]
        #else
            return [.accessoryCircular]
        #endif
    }
}

// MARK: - Bundle

@main struct TrioWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        TrioGlucoseComplication()
        TrioWatchComplication()
    }
}

extension View {
    func widgetBackground(backgroundView: some View) -> some View {
        if #available(watchOS 10.0, iOSApplicationExtension 17.0, iOS 17.0, *) {
            return containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            return background(backgroundView)
        }
    }
}
