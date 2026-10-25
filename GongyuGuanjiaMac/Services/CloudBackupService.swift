import Foundation
import SwiftData

// MARK: - 云端备份服务（users/<用户名>/backups/，与 iOS 版互通）

enum CloudBackupService {

    // MARK: 上传备份文件到云端

    /// 上传本地备份 zip 到云端（同名覆盖）
    @discardableResult
    static func uploadBackup(localURL: URL, config: CosConfig) async -> Result<String, String> {
        guard let data = try? Data(contentsOf: localURL) else { return .failure("读取本地备份失败") }
        let remotePath = CloudUser.backupPrefix + localURL.lastPathComponent
        do {
            try await CosUploader.upload(data: data, to: remotePath, contentType: "application/zip", config: config)
            return .success(remotePath)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// 下载云端备份到本地（同名），返回本地 URL
    @discardableResult
    static func downloadBackup(remoteName: String, config: CosConfig) async -> Result<URL, String> {
        let remotePath = CloudUser.backupPrefix + remoteName
        do {
            let data = try await CosUploader.fetchObjectData(path: remotePath, config: config)
            let local = DataRoot.backupsDirectory.appendingPathComponent(remoteName)
            try data.write(to: local)
            return .success(local)
        } catch let e as CosObjectNotFoundError {
            return .failure("云端备份不存在")
        } catch {
            return .failure(error.localizedDescription)
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

    /// 执行自动备份（快速备份 + 上传云端，失败静默）
    static func runAutoBackupIfNeeded(mainContext: ModelContext, houseContext: ModelContext?) {
        guard autoBackupEnabled else { return }
        // 距上次自动备份 < 6 小时则跳过
        let lastKey = "backup.autoLast"
        let last = UserDefaults.standard.double(forKey: lastKey)
        if Date().timeIntervalSince1970 - last < 6 * 3600 { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)

        Task {
            guard let config = CosConfig.load() else { return }
            // 快速备份：经营数据 zip（房源单独由房源同步管）
            let name = "快速备份_\(BackupTimestamp.string()).zip"
            let local = DataRoot.backupsDirectory.appendingPathComponent(name)
            let result = await DataBackupManager.createQuickBackup(mainContext: mainContext, to: local)
            if case .success = result {
                _ = await uploadBackup(localURL: local, config: config)
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
