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
struct ComplicationState: Codable, Equatable {
    /// When the phone produced the state (not when the watch received it).
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

    // Configuration chosen on the phone (Settings → Smart Watch → Apple Watch → Complication).
    // Optional so a snapshot written by an older build still decodes.
    var cornerValue: WatchComplicationValue?
    var secondaryValue: WatchComplicationValue?
    var staleMinutes: Int?

    // Numeric data for the gauge and chart complications. Optional for the same reason.
    /// "mg/dL" or "mmol/L" as sent by the phone.
    var units: String?
    /// Current glucose as a number in the user's units.
    var glucoseValue: Double?
    /// Up to the last three hours of readings, oldest first, user's units.
    var history: [ComplicationPoint]?

    static let placeholder = ComplicationState(
        date: .distantPast,
        glucose: "--",
        glucoseColorHex: "#ffffff",
        trend: "",
        delta: "--",
        iob: "--",
        cob: "--",
        lastLoopTime: "--"
    )

    /// Realistic sample used by the watch face gallery and the settings page previews.
    static func sample(
        units: String,
        cornerValue: WatchComplicationValue = WatchComplicationDefaults.cornerValue,
        secondaryValue: WatchComplicationValue = WatchComplicationDefaults.secondaryValue,
        staleMinutes: Int = WatchComplicationDefaults.staleMinutes,
        date: Date = Date()
    ) -> ComplicationState {
        let mmol = units.lowercased().hasPrefix("mmol")
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
            history: history
        )
    }

    var resolvedCornerValue: WatchComplicationValue { cornerValue ?? WatchComplicationDefaults.cornerValue }
    var resolvedSecondaryValue: WatchComplicationValue { secondaryValue ?? WatchComplicationDefaults.secondaryValue }

    /// Readings older than this are shown greyed out with their age.
    var staleAfter: TimeInterval {
        TimeInterval(staleMinutes ?? WatchComplicationDefaults.staleMinutes) * 60
    }

    /// True for mmol/L. Falls back to inspecting the formatted glucose when the phone
    /// did not send units (older build).
    var isMmol: Bool {
        if let units = units, !units.isEmpty {
            return units.lowercased().hasPrefix("mmol")
        }
        return glucose.contains(".") || glucose.contains(",")
    }

    /// Range of the gauge ring. Wide enough to show lows and highs, narrow enough that
    /// in-range values still move the needle.
    var gaugeRange: ClosedRange<Double> {
        isMmol ? 2.5 ... 16.0 : 45 ... 290
    }

    /// Current glucose clamped into `gaugeRange`, or nil when unknown.
    var gaugeValue: Double? {
        guard let value = glucoseValue, value.isFinite else { return nil }
        return min(max(value, gaugeRange.lowerBound), gaugeRange.upperBound)
    }

    /// Window the chart complication covers.
    static let chartWindow: TimeInterval = 3 * 60 * 60

    var trendArrow: String {
        switch trend {
        case "DoubleUp": return "⇈"
        case "SingleUp": return "↑"
        case "FortyFiveUp": return "↗"
        case "Flat": return "→"
        case "FortyFiveDown": return "↘"
        case "SingleDown": return "↓"
        case "DoubleDown": return "⇊"
        default: return ""
        }
    }

    func isStale(at reference: Date = Date()) -> Bool {
        reference.timeIntervalSince(date) > staleAfter
    }

    /// Text for a configurable slot. Empty when the slot is set to nothing or the value is unknown.
    func text(for value: WatchComplicationValue, labelled: Bool) -> String {
        switch value {
        case .nothing: return ""
        case .iob: return labelled ? "IOB \(iob)" : iob
        case .cob: return labelled ? "COB \(cob)" : cob
        case .delta: return "\(trendArrow) \(delta)".trimmingCharacters(in: .whitespaces)
        case .loopAge: return labelled ? "Loop \(lastLoopTime)" : lastLoopTime
        }
    }

    func minutesAgo(at reference: Date = Date()) -> Int {
        max(0, Int(reference.timeIntervalSince(date) / 60))
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
    /// Both watch targets set `INFOPLIST_KEY_AppGroupID = $(APP_GROUP_ID)`, which is
    /// `TRIO_APP_GROUP_ID` from `Config.xcconfig` and matches their entitlements, so the
    /// Info.plist key is the source of truth. The bundle-identifier derivation below is only
    /// a fallback for a project file that lost that build setting and assumes the default
    /// `org.nightscout.<TEAM>.trio` bundle identifier.
    static var appGroupID: String? {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
           !fromPlist.isEmpty, !fromPlist.hasPrefix("$(")
        {
            return fromPlist
        }
        guard let bundleID = Bundle.main.bundleIdentifier,
              let range = bundleID.range(of: ".watchkitapp")
        else { return nil }
        let base = String(bundleID[..<range.lowerBound])
        return "group.\(base).trio-app-group"
    }

    static var defaults: UserDefaults? {
        guard let id = appGroupID else { return nil }
        return UserDefaults(suiteName: id)
    }

    /// Writes the snapshot. Returns false when nothing changed, so callers can skip a
    /// WidgetKit reload and keep inside its refresh budget.
    @discardableResult static func save(_ state: ComplicationState) -> Bool {
        guard let defaults = defaults,
              let data = try? JSONEncoder().encode(state)
        else { return false }
        if let existing = defaults.data(forKey: key), existing == data {
            return false
        }
        defaults.set(data, forKey: key)
        return true
    }

    static func load() -> ComplicationState? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ComplicationState.self, from: data)
    }
}

extension Color {
    /// Parses "#RRGGBB" or "#RRGGBBAA" (hash optional). Returns nil for anything else.
    /// Named to avoid clashing with other hex initialisers in the iOS app.
    init?(complicationHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}
