import Foundation
import SwiftData

// MARK: - 云端房源同步（与 iOS 版同机制：共享账本 h/_houses.json + 媒体 h/<roomKey>/）

enum CloudSyncResult {
    case success(added: Int, updated: Int, removed: Int)
    case failure(String)
}

enum CloudHouseSync {

    // MARK: 上传本机全部房源到账本

    /// 把本地房源全量写入云端账本（覆盖写，最后写入优先，与 iOS 一致）
    static func pushAll(houseContext: ModelContext) async -> CloudSyncResult {
        guard let config = CosConfig.load() else { return .failure("未配置云存储") }
        var records: [CloudHouseRecord] = []
        do {
            let houses = try houseContext.fetch(FetchDescriptor<House>())
            for house in houses {
                guard house.isDeleted != true else { continue }
                let mediaNames = house.mediaItems.map { $0.fileName }
                records.append(CloudHouseRecord(
                    roomKey: house.mediaRoomKey,
                    roomNo: house.roomNo,
                    tower: house.tower,
                    landlord: house.landlord,
                    layout: house.layout,
                    price: Int(house.price),
                    password: house.password,
                    remark: house.remark,
                    status: house.status,
                    updatedAt: house.updatedAt,
                    updatedBy: CloudUser.username,
                    mediaNames: mediaNames
                ))
            }
            try await CloudHouseLedger.save(records, config: config)
            return .success(added: records.count, updated: 0, removed: 0)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: 从云端拉取并合并到本地

    /// 拉取云端账本合并进本地：
    /// - 云端有、本地无 → 新建本地房源（含媒体下载）
    /// - 两边都有 → 以 updatedAt 新者为准
    /// - 云端删除（不在账本但本地有 isDeleted=false）→ 本地标删除（仅当云端的 updatedAt 更新）
    static func pullAndMerge(houseContext: ModelContext, progress: ((Double, String) -> Void)? = nil) async -> CloudSyncResult {
        guard let config = CosConfig.load() else { return .failure("未配置云存储") }
        guard let cloudRecords = await CloudHouseLedger.fetch(config: config) else {
            return .failure("无法读取云端账本（未配置云函数地址或网络异常）")
        }

        let localHouses = (try? houseContext.fetch(FetchDescriptor<House>())) ?? []
        var localByKey: [String: House] = [:]
        for h in localHouses { localByKey[h.mediaRoomKey] = h }

        var added = 0, updated = 0, removed = 0
        let total = cloudRecords.count
        var done = 0

        for record in cloudRecords {
            done += 1
            progress?(Double(done) / Double(max(total, 1)), "同步 \(record.roomKey)…")

            if let local = localByKey[record.roomKey] {
                // 已存在：以较新者为准
                let cloudDate = record.updatedAt
                if cloudDate > local.updatedAt {
                    local.roomNo = record.roomNo
                    local.tower = record.tower
                    local.landlord = record.landlord
                    local.layout = record.layout
                    local.price = Double(record.price)
                    local.password = record.password
                    local.remark = record.remark
                    local.status = record.status
                    local.updatedAt = cloudDate
                    local.updatedBy = record.updatedBy
                    local.isDeleted = false
                    local.cloudStatus = .both
                    syncMediaNames(record.mediaNames, house: local, houseContext: houseContext)
                    updated += 1
                } else {
                    local.cloudStatus = .both
                }
            } else {
                // 本地没有 → 新建
                let house = House(
                    roomNo: record.roomNo, tower: record.tower, landlord: record.landlord,
                    layout: record.layout, price: Double(record.price),
                    password: record.password, remark: record.remark,
                    status: record.status
                )
                house.updatedAt = record.updatedAt
                house.updatedBy = record.updatedBy
                house.cloudStatus = .cloud
                houseContext.insert(house)
                syncMediaNames(record.mediaNames, house: house, houseContext: houseContext)
                added += 1
            }
            try? houseContext.save()
        }

        // 本地有、云端没有 → 云端已删除（仅当本地 not deleted 且本地更新时间早于云端账本创建？）
        // 与 iOS 一致：不自动删本地，只把「云端无记录」的本地房源标记为需要关注；这里不做删除。
        // removed 返回 0（iOS 也是保守策略：删除走「彻底删除」显式操作）

        progress?(1.0, "完成")
        return .success(added: added, updated: updated, removed: removed)
    }

    /// 同步媒体文件名关系（本地文件已存在的直接挂关系；不存在的留空，由媒体下载队列补）
    private static func syncMediaNames(_ names: [String], house: House, houseContext: ModelContext) {
        let existing = Set(house.mediaItems.map { $0.fileName })
        let want = Set(names)
        // 移除本地多余的关系
        for item in house.mediaItems where !want.contains(item.fileName) {
            houseContext.delete(item)
        }
        // 补缺失的关系
        for name in names where !existing.contains(name) {
            let kind = name.lowercased().hasSuffix(".mp4") || name.lowercased().hasSuffix(".mov")
                || name.lowercased().hasSuffix(".m4v") ? "video" : "image"
            house.mediaItems.append(MediaItem(fileName: name, kind: kind))
        }
    }

    // MARK: 下载缺失媒体

    /// 检查本地媒体是否齐全，缺的从 h/<roomKey>/ 下载
    static func downloadMissingMedia(house: House, config: CosConfig) async {
        let roomKey = house.mediaRoomKey
        for item in house.mediaItems {
            let localURL = MediaStore.fileURL(fileName: item.fileName, roomKey: roomKey)
            if FileManager.default.fileExists(atPath: localURL.path) { continue }
            let remoteName = item.kind == "video" ? CosUploader.cloudVideoName(for: item.fileName) : item.fileName
            guard let url = try? CosUploader.presignedGetURL(for: "h/\(roomKey)/\(remoteName)", expires: 3600, config: config) else { continue }
            if let data = try? await URLSession.shared.data(from: url) {
                let (d, resp) = data
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    MediaStore.save(data: d, fileName: item.fileName, roomKey: roomKey)
                }
            }
        }
    }
}
