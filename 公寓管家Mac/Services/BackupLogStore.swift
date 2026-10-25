import Foundation

// MARK: - 备份日志（本机操作记录 + 云端操作记录）

struct BackupLogEntry: Identifiable, Hashable {
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
        if let data = try? JSONEncoder().encode(logs.map {
            ["id": $0.id.uuidString, "time": $0.time.timeIntervalSince1970, "title": $0.title, "detail": $0.detail, "kind": $0.kind]
        }) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [BackupLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var out: [BackupLogEntry] = []
        for item in arr {
            guard let idStr = item["id"] as? String, let id = UUID(uuidString: idStr),
                  let time = item["time"] as? Double else { continue }
            out.append(BackupLogEntry(
                id: id, time: Date(timeIntervalSince1970: time),
                title: item["title"] as? String ?? "",
                detail: item["detail"] as? String ?? "",
                kind: item["kind"] as? String ?? "local"
            ))
        }
        return out
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
