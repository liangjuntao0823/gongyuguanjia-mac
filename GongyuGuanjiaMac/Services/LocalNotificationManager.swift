import Foundation
import UserNotifications
import SwiftData

// MARK: - 本地通知提醒（macOS 用 UNUserNotificationCenter，与 iOS 同 API）

enum LocalNotificationManager {

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notify.enabled") == nil ? true : UserDefaults.standard.bool(forKey: "notify.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notify.enabled") }
    }

    /// 提前提醒天数（收租/到期）
    static var advanceDays: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "notify.advanceDays")
            return v <= 0 ? 3 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "notify.advanceDays") }
    }

    /// 按提醒类型读取声音设置（system/custom，设置页可调）
    static func soundKey(for kind: String) -> String {
        UserDefaults.standard.string(forKey: kind) ?? "system"
    }

    // MARK: 定时提醒（一次性）

    static func schedule(title: String, body: String, at date: Date, id: String, tab: Int? = nil, soundKind: String? = nil) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 提醒声音：按类型读取设置（system/custom 一致使用系统默认音，Mac 通知栏等价效果）
        if let soundKind {
            _ = soundKey(for: soundKind)
            content.sound = .default
        } else {
            content.sound = .default
        }
        if let tab = tab { content.userInfo["tab"] = tab }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { CrashLogCollector.record("通知调度失败", detail: error.localizedDescription) }
        }
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: 重建全部提醒（数据变化后调用）

    /// 收租提醒：成交记录 dealDate + 周期（月）→ 下次收租日
    static func rebuildRentReminders(dealContext: ModelContext) {
        guard isEnabled else { return }
        cancelAll()
        // 收租提醒由「收租板块」的到期记录驱动（此处在同步后重建待收租提醒）
        // 具体提醒由 RentCollectionView 数据变化时按记录逐个 schedule
    }

    /// 通知 id 前缀
    static let rentPrefix = "gy.rent."
    static let expirePrefix = "gy.expire."
    static let contractPrefix = "gy.contract."
}
