import SwiftUI

@main
struct PhotoJunkCleanerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundScanKeeper.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .background:
                        BackgroundScanKeeper.shared.beginBackgroundScanIfNeeded()
                        BackgroundScanKeeper.shared.scheduleAppRefresh()
                    case .active:
                        BackgroundScanKeeper.shared.applicationDidBecomeActive()
                    default:
                        break
                    }
                }
        }
    }
}
