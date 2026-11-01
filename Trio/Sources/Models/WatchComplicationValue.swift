import Foundation

/// What a secondary slot of the Apple Watch glucose complication shows.
///
/// Shared by the iOS app (setting + picker), the watch app (carried in the
/// `WatchState` payload) and the complication extension (rendering), so it
/// must not depend on anything outside Foundation.
enum WatchComplicationValue: String, CaseIterable, Identifiable, Codable, Hashable {
    case nothing
    case iob
    case cob
    case delta
    case loopAge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nothing: return String(localized: "Nothing", comment: "Complication slot shows nothing")
        case .iob: return String(localized: "IOB", comment: "")
        case .cob: return String(localized: "COB", comment: "")
        case .delta: return String(localized: "Delta", comment: "")
        case .loopAge: return String(localized: "Loop Age", comment: "Minutes since the last loop")
        }
    }
}

/// Defaults shared by every target so the complication behaves the same before
/// the first settings payload arrives.
enum WatchComplicationDefaults {
    static let cornerValue: WatchComplicationValue = .iob
    static let secondaryValue: WatchComplicationValue = .delta
    static let staleMinutes = 15
    static let staleMinutesRange = 5 ... 30

    /// Keeps a stored or received value inside the range the Stepper can show.
    static func clampedStaleMinutes(_ minutes: Int) -> Int {
        min(max(minutes, staleMinutesRange.lowerBound), staleMinutesRange.upperBound)
    }
}
