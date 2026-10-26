import Foundation
import SwiftData

// MARK: - 云端备份服务（users/<用户名>/backups/，与 iOS 版互通）

enum CloudBackupService {

    // MARK: 上传备份文件到云端

    /// 上传本地备份 zip 到云端（同名覆盖）
    @discardableResult
    static func uploadBackup(localURL: URL, config: CosConfig) async -> Result<String, Error> {
        guard let data = try? Data(contentsOf: localURL) else { return .failure(AppError.message("读取本地备份失败")) }
        let remotePath = CloudUser.backupPrefix + localURL.lastPathComponent
        do {
            try await CosUploader.upload(data: data, to: remotePath, contentType: "application/zip", config: config)
            return .success(remotePath)
        } catch {
            return .failure(error)
        }
    }

    /// 下载云端备份到本地（同名），返回本地 URL
    @discardableResult
    static func downloadBackup(remoteName: String, config: CosConfig) async -> Result<URL, Error> {
        let remotePath = CloudUser.backupPrefix + remoteName
        do {
            let data = try await CosUploader.fetchObjectData(path: remotePath, config: config)
            let local = DataRoot.backupsDirectory.appendingPathComponent(remoteName)
            try data.write(to: local)
            return .success(local)
        } catch let e as CosObjectNotFoundError {
            return .failure(AppError.message("云端备份不存在"))
        } catch {
            return .failure(error)
        }
    }

    /// 列出云端备份（按修改时间倒序）
    static func listRemote(config: CosConfig) async -> [(name: String, size: Int64, date: Date)] {
        guard let items = try? await CosUploader.listObjects(prefix: CloudUser.backupPrefix, config: config) else { return [] }
        return items
            .filter { !$0.name.hasSuffix("/") }
            .sorted { $0.date > $1.date }
    }

    /// 删除云端备份
    static func deleteRemote(name: String, config: CosConfig) async -> Bool {
        let remotePath = CloudUser.backupPrefix + name
        return (try? await CosUploader.deleteObject(path: remotePath, config: config)) != nil
    }

    // MARK: 自动备份（v1.30：App 启动/后台自动备份并上传云端）

    /// 自动备份开关
    static var autoBackupEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "backup.autoEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "backup.autoEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "backup.autoEnabled") }
    }

    /// 自动备份频率（daily/weekly/monthly，设置页可调，与 iOS 同 key）
    static var autoBackupFrequency: String {
        get { UserDefaults.standard.string(forKey: "autoBackupFrequency") ?? "daily" }
        set { UserDefaults.standard.set(newValue, forKey: "autoBackupFrequency") }
    }

    /// 自动备份保留天数（默认 7，设置页可调）
    static var autoBackupRetentionDays: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "autoBackupRetentionDays")
            return v <= 0 ? 7 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "autoBackupRetentionDays") }
    }

    /// 按频率判断距上次备份是否到期
    private static func backupInterval() -> TimeInterval {
        switch autoBackupFrequency {
        case "weekly": return 7 * 24 * 3600
        case "monthly": return 30 * 24 * 3600
        default: return 24 * 3600
        }
    }

    /// 清理超过保留天数的自动备份（本地），手动备份不删除
    static func cleanupExpiredAutoBackups() {
        let days = autoBackupRetentionDays
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: DataRoot.backupsDirectory, includingPropertiesForKeys: [.creationDateKey], options: []) else { return }
        for url in files where url.lastPathComponent.hasPrefix("快速备份_") {
            guard let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else { continue }
            if Date().timeIntervalSince(date) > TimeInterval(days * 24 * 3600) {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// 执行自动备份（快速备份 + 上传云端，失败静默）
    static func runAutoBackupIfNeeded(mainContext: ModelContext, houseContext: ModelContext?) {
        guard autoBackupEnabled else { return }
        // 按频率判断：距上次自动备份不足一个周期则跳过
        let lastKey = "backup.autoLast"
        let last = UserDefaults.standard.double(forKey: lastKey)
        if Date().timeIntervalSince1970 - last < backupInterval() { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)

        Task {
            guard let config = CosConfig.load() else { return }
            // 快速备份：经营数据 zip（房源单独由房源同步管）
            let name = "快速备份_\(BackupTimestamp.string()).zip"
            let local = DataRoot.backupsDirectory.appendingPathComponent(name)
            let result = await DataBackupManager.createQuickBackup(mainContext: mainContext, to: local)
            if case .success = result {
                _ = await uploadBackup(localURL: local, config: config)
                cleanupExpiredAutoBackups()
            }
            _ = houseContext
        }
    }
}

// MARK: - 备份文件名时间戳（yyyyMMdd_HHmmss）

enum BackupTimestamp {
    static func string() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
