import Foundation
import SwiftUI

struct ComplicationPoint: Codable, Equatable {
    var t: TimeInterval
    var v: Double
}

struct ComplicationState: Codable, Equatable {
    var date: Date
    var glucose: String
    var glucoseColorHex: String
    var trend: String
    var delta: String
    var iob: String
    var cob: String
    var lastLoopTime: String

    var cornerValue: WatchComplicationValue
    var secondaryValue: WatchComplicationValue
    var staleMinutes: Int

    var units: String
    var glucoseValue: Double?
    var history: [ComplicationPoint]
    var loopDate: Date?
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

    static func sample(
        units: String,
        cornerValue: WatchComplicationValue = WatchComplicationDefaults.cornerValue,
        secondaryValue: WatchComplicationValue = WatchComplicationDefaults.secondaryValue,
        staleMinutes: Int = WatchComplicationDefaults.staleMinutes,
        date: Date = Date()
    ) -> ComplicationState {
        let mmol = Self.isMmol(units)
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

    static let chartWindow: TimeInterval = 3 * 60 * 60

    static func isMmol(_ units: String) -> Bool {
        units.lowercased().hasPrefix("mmol")
    }

    var isMmol: Bool { Self.isMmol(units) }

    var staleAfter: TimeInterval { TimeInterval(staleMinutes) * 60 }

    var gaugeRange: ClosedRange<Double> {
        isMmol ? 2.5 ... 16.0 : 45 ... 290
    }

    var inRangeBand: ClosedRange<Double> {
        if let low = lowLimit, let high = highLimit, low < high {
            return low ... high
        }
        return isMmol ? 3.9 ... 10.0 : 70 ... 180
    }

    var chartMinimumSpan: Double {
        isMmol ? 1 : 18
    }

    var gaugeValue: Double? {
        guard let value = glucoseValue, value.isFinite else { return nil }
        return min(max(value, gaugeRange.lowerBound), gaugeRange.upperBound)
    }

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

    private static let maxLoopAgeMinutes = 1440

    func isStale(at reference: Date) -> Bool {
        reference.timeIntervalSince(date) > staleAfter
    }

    func isLoopStale(at reference: Date) -> Bool {
        guard let loopDate = loopDate else { return false }
        return reference.timeIntervalSince(loopDate) > staleAfter
    }

    func loopAgeText(at reference: Date) -> String {
        guard let loopDate = loopDate else { return lastLoopTime }
        let minutes = max(0, Int(reference.timeIntervalSince(loopDate) / 60))
        return minutes > Self.maxLoopAgeMinutes ? "--" : "\(minutes) min"
    }

    func minutesAgo(at reference: Date) -> Int {
        max(0, Int(reference.timeIntervalSince(date) / 60))
    }

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

enum ComplicationStore {
    static let key = "ComplicationState.latest"

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
