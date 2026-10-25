import Foundation

// MARK: - 备份日志（本机操作记录 + 云端操作记录）

struct BackupLogEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let time: Date
    let title: String
    let detail: String
    let kind: String   // "local" / "cloud" / "backup" / "sync"
}

enum BackupLogStore {

    private static let key = "backup.logs.v1"
    private static let maxCount = 200

    static func log(_ title: String, detail: String, kind: String = "local") {
        let entry = BackupLogEntry(id: UUID(), time: Date(), title: title, detail: detail, kind: kind)
        var logs = load()
        logs.insert(entry, at: 0)
        if logs.count > maxCount { logs = Array(logs.prefix(maxCount)) }
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [BackupLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BackupLogEntry].self, from: data)) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
