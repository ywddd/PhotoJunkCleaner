import Foundation
import UIKit
import BackgroundTasks

/// 尽量在进后台后继续扫描一段时间，并在系统允许时调度后台刷新
@MainActor
final class BackgroundScanKeeper {
    static let shared = BackgroundScanKeeper()
    static let taskId = "com.yourname.PhotoJunkCleaner.scan"

    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private weak var engine: ScanEngine?

    private init() {}

    func bind(engine: ScanEngine) {
        self.engine = engine
    }

    /// App 启动时注册（iOS 13+）
    static func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await BackgroundScanKeeper.shared.handleAppRefresh(refresh)
            }
        }
    }

    func scheduleAppRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.taskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(req)
        } catch {
            // 模拟器 / 未授权时会失败，忽略
            print("BG schedule failed: \(error.localizedDescription)")
        }
    }

    /// 进入后台：申请额外执行时间，避免扫描立刻被挂起
    func beginBackgroundScanIfNeeded() {
        guard let engine, engine.isScanning else {
            endBackgroundTask()
            return
        }
        guard bgTask == .invalid else { return }

        bgTask = UIApplication.shared.beginBackgroundTask(withName: "PhotoJunkScan") { [weak self] in
            // 时间到：尽量保存进度提示，取消后台任务 id
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }

    func endBackgroundTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    /// 回到前台
    func applicationDidBecomeActive() {
        endBackgroundTask()
        // 若扫描被系统掐断，UI 上 isScanning 会在 engine 内自行收尾；用户可继续点扫描
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) async {
        scheduleAppRefresh()

        task.expirationHandler = {
            Task { @MainActor in
                // 到期只结束本轮后台，不强制 cancel 用户前台任务
            }
        }

        // 后台刷新窗口很短：若用户已有扫描在跑，尽量续一会儿
        if let engine, engine.isScanning {
            beginBackgroundScanIfNeeded()
            // 等最多 20s 或扫描结束
            for _ in 0..<40 {
                if !engine.isScanning { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            endBackgroundTask()
            task.setTaskCompleted(success: true)
        } else {
            task.setTaskCompleted(success: true)
        }
    }
}
