import SwiftUI
import WidgetKit

struct TrioGlucoseEntry: TimelineEntry {
    let date: Date
    let state: ComplicationState
    let isPlaceholder: Bool
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
        completion(Self.currentEntry(at: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioGlucoseEntry>) -> Void) {
        let now = Date()
        let current = Self.currentEntry(at: now)
        guard !current.isPlaceholder else {
            completion(Timeline(entries: [current], policy: .never))
            return
        }

        var dates = stride(from: 0, through: Self.timelineSpan, by: Self.timelineStep).map { now.addingTimeInterval($0) }
        let staleAt = current.state.date.addingTimeInterval(current.state.staleAfter + 1)
        if staleAt > now, staleAt < now.addingTimeInterval(Self.timelineSpan) {
            dates.append(staleAt)
        }
        let entries = dates.sorted().map { TrioGlucoseEntry(date: $0, state: current.state, isPlaceholder: false) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static let timelineStep: TimeInterval = 5 * 60
    private static let timelineSpan: TimeInterval = 2 * 60 * 60

    private static func currentEntry(at date: Date) -> TrioGlucoseEntry {
        if let state = ComplicationStore.load() {
            return TrioGlucoseEntry(date: date, state: state, isPlaceholder: false)
        }
        return TrioGlucoseEntry(date: date, state: .placeholder, isPlaceholder: true)
    }

    static var preview: ComplicationState {
        let units = ComplicationStore.load()?.units ?? "mg/dL"
        return ComplicationState.sample(units: units)
    }
}

struct TrioComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let kind: ComplicationKind
    let entry: TrioGlucoseEntry

    var body: some View {
        let model = ComplicationModel(
            kind: kind,
            state: entry.state,
            referenceDate: entry.date,
            isPlaceholder: entry.isPlaceholder,
            fullColor: renderingMode == .fullColor
        )
        switch family {
        case .accessoryRectangular:
            ComplicationRectangularContent(model: model)
                .widgetAccentable()
                .widgetBackground(backgroundView: Color.clear)
        case .accessoryInline:
            ComplicationInlineContent(model: model)
                .widgetBackground(backgroundView: Color.clear)
        #if os(watchOS)
            case .accessoryCorner:
                ComplicationCornerMain(model: model)
                    .widgetAccentable()
                    .widgetCurvesContent()
                    .widgetLabel {
                        ComplicationCornerLabel(model: model)
                    }
                    .widgetBackground(backgroundView: Color.clear)
        #endif
        default:
            ZStack {
                if kind != .gauge {
                    AccessoryWidgetBackground()
                }
                ComplicationCircularContent(model: model)
                    .widgetAccentable()
            }
            .widgetBackground(backgroundView: Color.clear)
        }
    }
}

private func families(for kind: ComplicationKind) -> [WidgetFamily] {
    kind.slots.compactMap { slot -> WidgetFamily? in
        switch slot {
        case .circular: return .accessoryCircular
        case .rectangular: return .accessoryRectangular
        case .inline: return .accessoryInline
        case .corner:
            #if os(watchOS)
                return .accessoryCorner
            #else
                return nil
            #endif
        }
    }
}

private func complicationConfiguration(for kind: ComplicationKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.widgetKind, provider: TrioGlucoseProvider()) { entry in
        TrioComplicationEntryView(kind: kind, entry: entry)
    }
    .configurationDisplayName(kind.displayName)
    .description(kind.summary)
    .supportedFamilies(families(for: kind))
}

// `Widget` needs an argument-less `init`, so each kind is its own small struct.

struct TrioGlucoseComplication: Widget {
    var body: some WidgetConfiguration { complicationConfiguration(for: .glucose) }
}

struct TrioGaugeComplication: Widget {
    var body: some WidgetConfiguration { complicationConfiguration(for: .gauge) }
}

struct TrioIobComplication: Widget {
    var body: some WidgetConfiguration { complicationConfiguration(for: .iob) }
}

struct TrioChartComplication: Widget {
    var body: some WidgetConfiguration { complicationConfiguration(for: .chart) }
}

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

@main struct TrioWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        TrioGlucoseComplication()
        TrioGaugeComplication()
        TrioIobComplication()
        TrioChartComplication()
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
