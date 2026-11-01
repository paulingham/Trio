import Foundation
import SwiftUI
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
        #expect(try decodeSettings(#"{"watchComplicationStaleMinutes": 999}"#).watchComplicationStaleMinutes == 30)
        #expect(WatchComplicationDefaults.clampedStaleMinutes(-3) == 5)
        #expect(WatchComplicationDefaults.clampedStaleMinutes(30) == 30)
    }

    @Test("Snapshot round-trips through the store encoding") func snapshotRoundTrips() throws {
        let sample = ComplicationState.sample(units: "mg/dL", cornerValue: .cob, secondaryValue: .loopAge, staleMinutes: 25)
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(ComplicationState.self, from: data)
        #expect(decoded == sample)
        #expect(!decoded.isMmol)
        #expect(decoded.history.count == 36)
        #expect(decoded.cornerValue == .cob)
        #expect(decoded.staleAfter == 25 * 60)
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
        state.staleMinutes = WatchComplicationDefaults.staleMinutes
        #expect(!state.isStale(at: now.addingTimeInterval(14 * 60)))
        #expect(state.isStale(at: now.addingTimeInterval(16 * 60)))
    }

    @Test("Slot text follows the chosen value") func slotText() {
        var state = ComplicationState.sample(units: "mmol/L")
        state.trend = "FortyFiveUp"
        state.delta = "+0.3"
        #expect(state.trendArrow == "↗︎")
        #expect(state.text(for: .nothing, labelled: true) == "")
        #expect(state.text(for: .iob, labelled: true) == "IOB 1.25")
        #expect(state.text(for: .iob, labelled: false) == "1.25")
        #expect(state.text(for: .cob, labelled: true) == "COB 12")
        #expect(state.text(for: .delta, labelled: true) == "↗︎ +0.3")
        #expect(state.text(for: .loopAge, labelled: true) == "Loop 2 min")
        state.trend = "Unknown"
        #expect(state.trendArrow == "")
        #expect(state.text(for: .delta, labelled: false) == "+0.3")
    }

    @Test("Loop staleness is separate from reading staleness") func loopStaleness() {
        let now = Date()
        var state = ComplicationState.sample(units: "mmol/L", staleMinutes: 15, date: now)
        state.loopDate = now.addingTimeInterval(-20 * 60)
        let model = ComplicationModel(kind: .iob, state: state, referenceDate: now)
        #expect(!model.isStale)
        #expect(model.isLoopStale)
        #expect(model.valueColor == .gray)
        #expect(model.iobStatusText == "loop 2 min")
        state.loopDate = nil
        #expect(!state.isLoopStale(at: now.addingTimeInterval(3600)))
    }

    @Test("Ring and chart band follow the user's limits") func inRangeBand() {
        var state = ComplicationState.sample(units: "mg/dL")
        #expect(state.inRangeBand == 70 ... 180)
        state.lowLimit = 80
        state.highLimit = 160
        #expect(state.inRangeBand == 80 ... 160)
        state.highLimit = 60
        #expect(state.inRangeBand == 70 ... 180)
        let model = ComplicationModel(kind: .gauge, state: state, referenceDate: state.date)
        #expect(model.gaugeGradient.stops.first?.color == .red)
        #expect(model.gaugeGradient.stops.count == 5)
    }

    @Test("Placeholder has no reading and a neutral colour") func placeholder() {
        let state = ComplicationState.placeholder
        #expect(state.gaugeValue == nil)
        let model = ComplicationModel(kind: .gauge, state: state, referenceDate: Date(), isPlaceholder: true)
        #expect(model.gaugeValue == (45.0 + 290.0) / 2)
        #expect(model.gaugeGradient == Gradient(colors: [.gray, .gray]))
        #expect(state.history.isEmpty)
        #expect(state.trendArrow == "")
        #expect(Color(complicationHex: "#4cd964") != nil)
        #expect(Color(complicationHex: "4cd964ff") == nil)
        #expect(Color(complicationHex: "zzz") == nil)
    }
}
