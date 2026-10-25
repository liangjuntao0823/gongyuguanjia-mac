import Foundation
import SwiftData

// MARK: - BackupV5Manager：备份中心的统一入口（快速/全量 + 云端同步 + 历史管理）
// iOS 版 v1.40 起快速备份包含经营数据与房源字段；全量另含媒体镜像。

enum BackupV5Manager {

    /// 本地备份历史（读取备份目录 zip，按修改时间倒序）
    static func localBackups() -> [(url: URL, date: Date, size: Int64, isFull: Bool)] {
        let dir = DataRoot.backupsDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        var result: [(url: URL, date: Date, size: Int64, isFull: Bool)] = []
        for name in names where name.hasSuffix(".zip") {
            let url = dir.appendingPathComponent(name)
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            let date = (attr?[.modificationDate] as? Date) ?? .distantPast
            let size = (attr?[.size] as? Int64) ?? 0
            let isFull = name.contains("全量")
            result.append((url, date, size, isFull))
        }
        return result.sorted { $0.date > $1.date }
    }

    /// 云端备份历史
    static func cloudBackups(config: CosConfig) async -> [(name: String, size: Int64, date: Date)] {
        await CloudBackupService.listRemote(config: config)
    }

    /// 执行快速备份（本地 + 自动上传云端）
    static func runQuickBackup(mainContext: ModelContext, houseContext: ModelContext, uploadCloud: Bool) async -> BackupResult {
        let name = "快速备份_\(BackupTimestamp.string()).zip"
        let local = DataRoot.backupsDirectory.appendingPathComponent(name)
        let result = await DataBackupManager.createQuickBackup(mainContext: mainContext, to: local)
        if case .success = result, uploadCloud, let config = CosConfig.load() {
            _ = await CloudBackupService.uploadBackup(localURL: local, config: config)
        }
        return result
    }

    /// 执行全量备份（本地 + 自动上传云端）
    static func runFullBackup(mainContext: ModelContext, houseContext: ModelContext, uploadCloud: Bool) async -> BackupResult {
        let name = "全量备份_\(BackupTimestamp.string()).zip"
        let local = DataRoot.backupsDirectory.appendingPathComponent(name)
        let result = await DataBackupManager.createFullBackup(mainContext: mainContext, houseContext: houseContext, to: local)
        if case .success = result, uploadCloud, let config = CosConfig.load() {
            _ = await CloudBackupService.uploadBackup(localURL: local, config: config)
        }
        return result
    }

    /// 恢复本地备份
    static func restoreLocal(url: URL, mainContext: ModelContext, houseContext: ModelContext) async -> Result<Bool, String> {
        await DataBackupManager.restore(from: url, mainContext: mainContext, houseContext: houseContext)
    }

    /// 恢复云端备份（先下载再恢复）
    static func restoreCloud(name: String, config: CosConfig, mainContext: ModelContext, houseContext: ModelContext) async -> Result<Bool, String> {
        let result = await CloudBackupService.downloadBackup(remoteName: name, config: config)
        switch result {
        case .success(let url):
            return await DataBackupManager.restore(from: url, mainContext: mainContext, houseContext: houseContext)
        case .failure(let e):
            return .failure(e)
        }
    }

    /// 删除本地备份
    static func deleteLocal(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 删除云端备份
    static func deleteCloud(name: String, config: CosConfig) async {
        _ = await CloudBackupService.deleteRemote(name: name, config: config)
    }
}
