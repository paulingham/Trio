import SwiftUI
import UserNotifications
import WatchConnectivity
import WatchKit

@main struct TrioWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchNotificationHandler.shared.configure()
        WatchLogger.shared.info(.lifecycle, "App launched")
    }

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .background {
                WatchLogger.shared.info(.lifecycle, "App moved to background")
                WatchLogger.shared.didEnterBackground()
                WatchBackgroundRefresh.schedule()
            }
        }
        .backgroundTask(.appRefresh) {
            await WatchBackgroundRefresh.run()
        }
    }
}

enum WatchBackgroundRefresh {
    static let interval: TimeInterval = 15 * 60
    private static let activationTimeout: TimeInterval = 5
    private static let activationPoll: TimeInterval = 0.25
    private static let processingGrace: TimeInterval = 2

    static func schedule() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: interval),
            userInfo: nil
        ) { error in
            if let error = error {
                Task { await WatchLogger.shared.log("⌚️ Background refresh scheduling failed: \(error)") }
            }
        }
    }

    static func run() async {
        let state = WatchState.current ?? WatchState()
        await waitForActivation()
        state.ingestReceivedApplicationContext()
        try? await Task.sleep(for: .seconds(processingGrace))
        schedule()
    }

    private static func waitForActivation() async {
        let deadline = Date(timeIntervalSinceNow: activationTimeout)
        while WCSession.default.activationState != .activated, Date() < deadline {
            try? await Task.sleep(for: .seconds(activationPoll))
        }
    }
}
