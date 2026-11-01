import Foundation
import SwiftUI

/// One historical glucose reading for the chart complication. Short keys keep the
/// App Group payload small.
struct ComplicationPoint: Codable, Equatable {
    /// Seconds since 1970.
    var t: TimeInterval
    /// Glucose in the user's units.
    var v: Double
}

/// Compact snapshot of the values shown on the watch face complications.
///
/// Written by the watch app every time a `WatchState` arrives from the phone
/// (foreground message or background `transferUserInfo`), read by the
/// `Trio Watch Complication Extension`. Both targets compile this file and share
/// the App Group container, which is the only storage a WidgetKit extension can
/// read that the host app can write. The iOS app also compiles it so the settings
/// page can render previews of the complications with sample data.
///
/// If the stored JSON ever fails to decode, `ComplicationStore.load()` returns nil, the
/// face shows the placeholder, and the next payload from the phone rewrites it.
struct ComplicationState: Codable, Equatable {
    /// Time of the latest reading the snapshot describes.
    var date: Date
    /// Glucose already formatted in the user's units by the phone, e.g. "7.2" or "130".
    var glucose: String
    /// Hex colour string the phone chose for the glucose value, e.g. "#ffffff".
    var glucoseColorHex: String
    /// Nightscout direction name, e.g. "FortyFiveUp". Empty when unknown.
    var trend: String
    /// Signed delta formatted by the phone, e.g. "+0.3" or "-2".
    var delta: String
    /// IOB formatted by the phone, two fraction digits.
    var iob: String
    /// COB formatted by the phone, integer grams.
    var cob: String
    /// Last loop age as sent by the phone, e.g. "3 min" or "--".
    var lastLoopTime: String

    // Configuration chosen on the phone (Settings → Smart Watch → Apple Watch → Complication Settings).
    var cornerValue: WatchComplicationValue
    var secondaryValue: WatchComplicationValue
    var staleMinutes: Int

    /// "mg/dL" or "mmol/L" as sent by the phone.
    var units: String
    /// Current glucose as a number in the user's units; nil when there is no reading.
    var glucoseValue: Double?
    /// Readings inside `chartWindow`, oldest first, user's units.
    var history: [ComplicationPoint]
    /// When the loop last ran; nil when the phone did not say.
    var loopDate: Date?
    /// The user's low and high limits in their units; nil when the phone did not say.
    var lowLimit: Double?
    var highLimit: Double?

    static let placeholder = ComplicationState(
        date: .distantPast,
        glucose: "--",
        glucoseColorHex: "#ffffff",
        trend: "",
        delta: "--",
        iob: "--",
        cob: "--",
        lastLoopTime: "--",
        cornerValue: WatchComplicationDefaults.cornerValue,
        secondaryValue: WatchComplicationDefaults.secondaryValue,
        staleMinutes: WatchComplicationDefaults.staleMinutes,
        units: "mg/dL",
        glucoseValue: nil,
        history: [],
        loopDate: nil,
        lowLimit: nil,
        highLimit: nil
    )

    /// Realistic sample used by the watch face gallery and the settings page previews.
    static func sample(
        units: String,
        cornerValue: WatchComplicationValue = WatchComplicationDefaults.cornerValue,
        secondaryValue: WatchComplicationValue = WatchComplicationDefaults.secondaryValue,
        staleMinutes: Int = WatchComplicationDefaults.staleMinutes,
        date: Date = Date()
    ) -> ComplicationState {
        let mmol = Self.isMmol(units)
        // A gentle fall into range then a slow rise after a meal, 5 minute spacing over 3 hours.
        let mmolCurve: [Double] = [
            8.9, 8.6, 8.3, 8.0, 7.7, 7.4, 7.1, 6.9, 6.7, 6.5, 6.3, 6.1,
            6.0, 5.9, 5.8, 5.8, 5.7, 5.7, 5.8, 5.9, 6.1, 6.3, 6.6, 6.9,
            7.1, 7.2, 7.2, 7.1, 7.0, 6.9, 6.8, 6.7, 6.6, 6.5, 6.4, 6.4
        ]
        let curve = mmol ? mmolCurve : mmolCurve.map { ($0 * 18.0182).rounded() }
        let start = date.timeIntervalSince1970 - TimeInterval(curve.count - 1) * 300
        let history = curve.enumerated().map { ComplicationPoint(t: start + TimeInterval($0.offset) * 300, v: $0.element) }
        return ComplicationState(
            date: date,
            glucose: mmol ? "6.4" : "115",
            glucoseColorHex: "#4cd964",
            trend: "Flat",
            delta: mmol ? "+0.0" : "0",
            iob: "1.25",
            cob: "12",
            lastLoopTime: "2 min",
            cornerValue: cornerValue,
            secondaryValue: secondaryValue,
            staleMinutes: staleMinutes,
            units: units,
            glucoseValue: curve.last,
            history: history,
            loopDate: date.addingTimeInterval(-2 * 60),
            lowLimit: mmol ? 3.9 : 70,
            highLimit: mmol ? 10.0 : 180
        )
    }

    /// Window the chart complication covers.
    static let chartWindow: TimeInterval = 3 * 60 * 60

    static func isMmol(_ units: String) -> Bool {
        units.lowercased().hasPrefix("mmol")
    }

    var isMmol: Bool { Self.isMmol(units) }

    /// Readings older than this are shown greyed out with their age.
    var staleAfter: TimeInterval { TimeInterval(staleMinutes) * 60 }

    /// Range of the gauge ring. Wide enough to show lows and highs, narrow enough that
    /// in-range values still move the needle.
    var gaugeRange: ClosedRange<Double> {
        isMmol ? 2.5 ... 16.0 : 45 ... 290
    }

    /// The user's in-range band, used for the chart background and the green part of the
    /// ring. Falls back to a typical band when the phone has not sent the limits.
    var inRangeBand: ClosedRange<Double> {
        if let low = lowLimit, let high = highLimit, low < high {
            return low ... high
        }
        return isMmol ? 3.9 ... 10.0 : 70 ... 180
    }

    /// Smallest vertical span the chart draws, so a flat trace is not blown up to noise.
    var chartMinimumSpan: Double {
        isMmol ? 1 : 18
    }

    /// Current glucose clamped into `gaugeRange`, or nil when unknown.
    var gaugeValue: Double? {
        guard let value = glucoseValue, value.isFinite else { return nil }
        return min(max(value, gaugeRange.lowerBound), gaugeRange.upperBound)
    }

    /// Arrow for the Nightscout direction name, matching `BloodGlucose.Direction.symbol`
    /// on the phone (not available to the watch targets).
    var trendArrow: String {
        switch trend {
        case "TripleUp": return "↑↑↑"
        case "DoubleUp": return "↑↑"
        case "SingleUp": return "↑"
        case "FortyFiveUp": return "↗︎"
        case "Flat": return "→"
        case "FortyFiveDown": return "↘︎"
        case "SingleDown": return "↓"
        case "DoubleDown": return "↓↓"
        case "TripleDown": return "↓↓↓"
        default: return ""
        }
    }

    func isStale(at reference: Date) -> Bool {
        reference.timeIntervalSince(date) > staleAfter
    }

    /// True when the loop has not run within the stale threshold, so IOB and COB may be out of
    /// date even though the CGM is still reporting. False when the phone sent no loop date.
    func isLoopStale(at reference: Date) -> Bool {
        guard let loopDate = loopDate else { return false }
        return reference.timeIntervalSince(loopDate) > staleAfter
    }

    func minutesAgo(at reference: Date) -> Int {
        max(0, Int(reference.timeIntervalSince(date) / 60))
    }

    /// Text for a configurable slot. Empty when the slot is set to nothing.
    func text(for value: WatchComplicationValue, labelled: Bool) -> String {
        switch value {
        case .nothing: return ""
        case .iob: return labelled ? "IOB \(iob)" : iob
        case .cob: return labelled ? "COB \(cob)" : cob
        case .delta: return "\(trendArrow) \(delta)".trimmingCharacters(in: .whitespaces)
        case .loopAge: return labelled ? "Loop \(lastLoopTime)" : lastLoopTime
        }
    }

    var glucoseColor: Color {
        Color(complicationHex: glucoseColorHex) ?? .white
    }
}

/// Persists `ComplicationState` in the shared App Group `UserDefaults`.
enum ComplicationStore {
    static let key = "ComplicationState.latest"

    /// The App Group identifier shared by the watch app and the complication extension.
    ///
    /// Read from the `AppGroupID` Info.plist key when the build puts it there. The watch targets
    /// use generated Info.plists and the key has been seen missing from them, so the identifier
    /// is otherwise derived from the bundle identifier:
    /// `org.nightscout.<TEAM>.trio.watchkitapp[.TrioWatchComplication]` →
    /// `group.org.nightscout.<TEAM>.trio.trio-app-group`, which is `TRIO_APP_GROUP_ID` in
    /// `Config.xcconfig` and what the entitlements use.
    static var appGroupID: String? {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
           !fromPlist.isEmpty, !fromPlist.hasPrefix("$(")
        {
            return fromPlist
        }
        guard let bundleID = Bundle.main.bundleIdentifier,
              let range = bundleID.range(of: ".watchkitapp")
        else { return nil }
        return "group.\(bundleID[..<range.lowerBound]).trio-app-group"
    }

    static let defaults: UserDefaults? = appGroupID.flatMap { UserDefaults(suiteName: $0) }

    private static var lastSaved: ComplicationState?

    /// Writes the snapshot. Returns false when it matches the last one written by this
    /// process, so callers can skip a WidgetKit reload and keep inside its refresh budget.
    @discardableResult static func save(_ state: ComplicationState) -> Bool {
        guard state != lastSaved,
              let defaults = defaults,
              let data = try? JSONEncoder().encode(state)
        else { return false }
        defaults.set(data, forKey: key)
        lastSaved = state
        return true
    }

    static func load() -> ComplicationState? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ComplicationState.self, from: data)
    }
}

extension Color {
    /// Parses "#RRGGBB" (hash optional), the form `Color.toHexString()` produces on the phone.
    /// Returns nil for anything else. Named to avoid clashing with other hex initialisers.
    init?(complicationHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
