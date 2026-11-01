import Foundation
import SwiftUI

/// Compact snapshot of the values shown on the watch face complications.
///
/// Written by the watch app every time a `WatchState` arrives from the phone
/// (foreground message or background `transferUserInfo`), read by the
/// `Trio Watch Complication Extension`. Both targets compile this file and share
/// the App Group container, which is the only storage a WidgetKit extension can
/// read that the host app can write.
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

    var resolvedCornerValue: WatchComplicationValue { cornerValue ?? WatchComplicationDefaults.cornerValue }
    var resolvedSecondaryValue: WatchComplicationValue { secondaryValue ?? WatchComplicationDefaults.secondaryValue }

    /// Readings older than this are shown greyed out with their age.
    var staleAfter: TimeInterval {
        TimeInterval(staleMinutes ?? WatchComplicationDefaults.staleMinutes) * 60
    }

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
        Color(hex: glucoseColorHex) ?? .white
    }
}

/// Persists `ComplicationState` in the shared App Group `UserDefaults`.
enum ComplicationStore {
    static let key = "ComplicationState.latest"

    /// The App Group identifier shared by the watch app and the complication extension.
    ///
    /// The watch targets use Xcode-generated Info.plists, so unlike the iOS app there is no
    /// `AppGroupID` key to read. The group is derived from the bundle identifier instead:
    /// `org.nightscout.<TEAM>.trio.watchkitapp[.TrioWatchComplication]`
    /// → `group.org.nightscout.<TEAM>.trio.trio-app-group`, which is exactly
    /// `TRIO_APP_GROUP_ID` from `Config.xcconfig`. An `AppGroupID` Info.plist key, if present,
    /// takes precedence.
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

    static func save(_ state: ComplicationState) {
        guard let defaults = defaults,
              let data = try? JSONEncoder().encode(state)
        else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> ComplicationState? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ComplicationState.self, from: data)
    }
}

extension Color {
    /// Parses "#RRGGBB" or "#RRGGBBAA" (hash optional). Returns nil for anything else.
    init?(hex: String) {
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
