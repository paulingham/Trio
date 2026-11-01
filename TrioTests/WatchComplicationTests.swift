import Foundation
import Testing
@testable import Trio

@Suite("Watch Complication") struct WatchComplicationTests {
    private func decodeSettings(_ json: String) throws -> TrioSettings {
        try JSONDecoder().decode(TrioSettings.self, from: Data(json.utf8))
    }

    @Test("Settings without complication keys use the defaults") func settingsDefaults() throws {
        let settings = try decodeSettings("{}")
        #expect(settings.watchComplicationCornerValue == WatchComplicationDefaults.cornerValue)
        #expect(settings.watchComplicationSecondaryValue == WatchComplicationDefaults.secondaryValue)
        #expect(settings.watchComplicationStaleMinutes == WatchComplicationDefaults.staleMinutes)
    }

    @Test("Stored complication settings decode") func settingsDecode() throws {
        let json = #"""
        {"watchComplicationCornerValue": "cob", "watchComplicationSecondaryValue": "loopAge",
         "watchComplicationStaleMinutes": 30}
        """#
        let settings = try decodeSettings(json)
        #expect(settings.watchComplicationCornerValue == .cob)
        #expect(settings.watchComplicationSecondaryValue == .loopAge)
        #expect(settings.watchComplicationStaleMinutes == 30)
    }

    @Test("Out-of-range stale minutes are clamped on decode") func staleMinutesClamped() throws {
        #expect(try decodeSettings(#"{"watchComplicationStaleMinutes": 0}"#).watchComplicationStaleMinutes == 5)
        #expect(try decodeSettings(#"{"watchComplicationStaleMinutes": 999}"#).watchComplicationStaleMinutes == 60)
        #expect(WatchComplicationDefaults.clampedStaleMinutes(-3) == 5)
        #expect(WatchComplicationDefaults.clampedStaleMinutes(30) == 30)
    }

    @Test("Unknown raw values fall back") func unknownRawValueFallsBack() {
        #expect(WatchComplicationValue.from("bogus", default: .iob) == .iob)
        #expect(WatchComplicationValue.from(nil, default: .delta) == .delta)
        #expect(WatchComplicationValue.from("cob", default: .iob) == .cob)
    }

    @Test("Snapshot from an older build still decodes") func legacySnapshotDecodes() throws {
        let json = #"""
        {"date": 0, "glucose": "6.4", "glucoseColorHex": "#4cd964", "trend": "Flat",
         "delta": "+0.1", "iob": "1.25", "cob": "12", "lastLoopTime": "2 min"}
        """#
        let state = try JSONDecoder().decode(ComplicationState.self, from: Data(json.utf8))
        #expect(state.resolvedCornerValue == WatchComplicationDefaults.cornerValue)
        #expect(state.resolvedSecondaryValue == WatchComplicationDefaults.secondaryValue)
        #expect(state.staleAfter == TimeInterval(WatchComplicationDefaults.staleMinutes * 60))
        #expect(state.isMmol)
        #expect(state.gaugeValue == nil)
        #expect(state.history == nil)
    }

    @Test("Snapshot round-trips through the store encoding") func snapshotRoundTrips() throws {
        let sample = ComplicationState.sample(units: "mg/dL", cornerValue: .cob, secondaryValue: .loopAge, staleMinutes: 25)
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(ComplicationState.self, from: data)
        #expect(decoded == sample)
        #expect(!decoded.isMmol)
        #expect(decoded.history?.count == 36)
    }

    @Test("Units decide the gauge range and clamp the value") func gaugeRange() {
        var state = ComplicationState.sample(units: "mmol/L")
        #expect(state.gaugeRange == 2.5 ... 16.0)
        state.glucoseValue = 25
        #expect(state.gaugeValue == 16.0)
        state.glucoseValue = 1
        #expect(state.gaugeValue == 2.5)

        state = ComplicationState.sample(units: "mg/dL")
        #expect(state.gaugeRange == 45 ... 290)
        #expect(state.gaugeValue == 115)
    }

    @Test("Staleness follows the configured minutes") func staleness() {
        let now = Date()
        var state = ComplicationState.sample(units: "mg/dL", staleMinutes: 10, date: now)
        #expect(!state.isStale(at: now.addingTimeInterval(9 * 60)))
        #expect(state.isStale(at: now.addingTimeInterval(11 * 60)))
        #expect(state.minutesAgo(at: now.addingTimeInterval(11 * 60)) == 11)
        state.staleMinutes = nil
        #expect(!state.isStale(at: now.addingTimeInterval(14 * 60)))
        #expect(state.isStale(at: now.addingTimeInterval(16 * 60)))
    }

    @Test("Slot text follows the chosen value") func slotText() {
        var state = ComplicationState.sample(units: "mmol/L")
        state.trend = "FortyFiveUp"
        state.delta = "+0.3"
        #expect(state.trendArrow == "↗")
        #expect(state.text(for: .nothing, labelled: true) == "")
        #expect(state.text(for: .iob, labelled: true) == "IOB 1.25")
        #expect(state.text(for: .iob, labelled: false) == "1.25")
        #expect(state.text(for: .cob, labelled: true) == "COB 12")
        #expect(state.text(for: .delta, labelled: true) == "↗ +0.3")
        #expect(state.text(for: .loopAge, labelled: true) == "Loop 2 min")
        state.trend = "Unknown"
        #expect(state.trendArrow == "")
        #expect(state.text(for: .delta, labelled: false) == "+0.3")
    }

    @Test("Chart points are limited to the window") func chartWindow() {
        let now = Date()
        var state = ComplicationState.sample(units: "mg/dL", date: now)
        let old = ComplicationPoint(t: now.timeIntervalSince1970 - ComplicationState.chartWindow - 60, v: 100)
        state.history = [old] + (state.history ?? [])
        let model = ComplicationModel(kind: .chart, state: state, referenceDate: now)
        #expect(model.chartPoints.count == 36)
        #expect(model.chartPoints.first?.v != 100)
    }
}
