import Foundation
import SwiftData

// MARK: - 云端房源同步（与 iOS 版同机制：一房一文件账本 h/<roomKey>/info.json + 媒体同目录）
// v1.2.1 对齐 iOS v1.71 方案 A：不再使用 h/_houses.json 汇总文件；
// 状态值域英文(available/rented)、房号带 1-/2- 前缀、404=空账本、云端删除跟随删除、同步差异确认

enum CloudSyncResult {
    case success(added: Int, updated: Int, removed: Int, detail: String)
    case failure(String)
}

enum CloudHouseSync {

    // MARK: 账本边界转换（纯函数，只抄功能不复制代码）

    /// 本地状态 → 云端英文值域（iOS HouseStatus.rawValue）
    static func statusToCloud(_ status: String) -> String {
        status == "已租" ? "rented" : "available"
    }

    /// 云端值域 → 本地中文（兼容历史：云端已是中文则原样保留）
    static func statusFromCloud(_ raw: String) -> String {
        switch raw {
        case "rented": return "已租"
        case "available": return "待租"
        case "已租", "待租": return raw
        default: return "待租"
        }
    }

    /// 本地房号本体 → 云端带前缀房号（1 座 1-xxx、2 座 2-xxx，与 iOS 一致）
    static func roomNoToCloud(_ roomNo: String, tower: Int) -> String {
        if tower == 2 && !roomNo.hasPrefix("2-") { return "2-\(roomNo)" }
        if tower == 1 && !roomNo.hasPrefix("1-") { return "1-\(roomNo)" }
        return roomNo
    }

    /// 云端房号 → 本地房号本体（剥离 1-/2- 前缀，防本地出现双前缀）
    static func roomNoFromCloud(_ roomNo: String) -> String {
        if roomNo.hasPrefix("2-") || roomNo.hasPrefix("1-") {
            return String(roomNo.dropFirst(2))
        }
        return roomNo
    }

    // MARK: 上传本机全部房源到账本（一房一文件）

    /// 单套账本对象路径（媒体与账本同目录，与 iOS recordPath 一致）
    static func recordPath(roomKey: String) -> String {
        "h/\(roomKey)/info.json"
    }

    /// 由本地房源构造账本记录（与 iOS record(from:username:) 同构：roomNo 无前缀、状态英文、媒体名清单）
    static func record(from house: House) -> CloudHouseRecord {
        CloudHouseRecord(
            roomKey: house.mediaRoomKey,
            roomNo: house.roomNo,
            tower: house.tower,
            landlord: house.landlord,
            layout: house.layout,
            price: Int(house.price),
            password: house.password,
            remark: house.remark,
            status: statusToCloud(house.status),
            updatedAt: house.lastUpdatedAt ?? house.updatedAt,
            updatedBy: CloudUser.username,
            mediaNames: house.mediaItems.map { $0.fileName }
        )
    }

    /// 媒体名归一化 key（与 iOS mediaNormKey 一致）：去扩展名 + 小写，.mov/.mp4 视为同一文件
    static func mediaNormKey(_ name: String) -> String {
        (name as NSString).deletingPathExtension.lowercased()
    }

    /// 字段级对比（与 iOS cloudRecordDiffers 一致）：逐字段比较，不依赖时间戳
    static func cloudRecordDiffers(_ rec: CloudHouseRecord, from house: House) -> Bool {
        if rec.roomNo != house.roomNo { return true }
        if rec.tower != house.tower { return true }
        if rec.landlord != house.landlord { return true }
        if rec.layout != house.layout { return true }
        if rec.price != Int(house.price) { return true }
        if rec.password != house.password { return true }
        if rec.remark != house.remark { return true }
        if rec.status != statusToCloud(house.status) { return true }
        let localMedia = Set(house.mediaItems.map { mediaNormKey($0.fileName) })
        if localMedia != Set(rec.mediaNames.map { mediaNormKey($0) }) { return true }
        return false
    }

    /// 把本地房源逐套写入云端账本（修改一套只写一套，最后写入优先，与 iOS v1.71 一致）
    static func pushAll(houseContext: ModelContext) async -> CloudSyncResult {
        guard let config = CosConfig.load() else { return .failure("未配置云存储") }
        do {
            let houses = try houseContext.fetch(FetchDescriptor<House>())
            var pushed = 0
            var removed = 0
            for house in houses {
                if house.isDeleted == true {
                    // 本地已删除（回收站/彻底删除）→ 云端账本删除该套（媒体目录保留，恢复不丢图）
                    try? await CosUploader.deleteObject(path: recordPath(roomKey: house.mediaRoomKey), config: config)
                    removed += 1
                    continue
                }
                try await saveRecord(record(from: house), config: config)
                pushed += 1
            }
            let detail = "已上传 \(pushed) 套" + (removed > 0 ? "，云端删除 \(removed) 套" : "")
            return .success(added: pushed, updated: 0, removed: removed, detail: detail)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// 写单套账本（覆盖写，日期用默认编码，与 iOS upload(record:) 完全一致——iOS 读不了 ISO8601 字符串时间戳）
    static func saveRecord(_ record: CloudHouseRecord, config: CosConfig) async throws {
        let data = try JSONEncoder().encode(record)
        try await CosUploader.upload(data: data, to: recordPath(roomKey: record.roomKey),
                                     contentType: "application/json", config: config)
    }

    /// 拉取云端全部账本（一房一文件）：列出 h/ 下全部对象 → 过滤各房 info.json → 并发读取
    /// 404（某套无 info.json）跳过该套；列表/网络/非 404 一律报错（绝不当作空账本误删本地）
    static func fetchAll(config: CosConfig) async throws -> [CloudHouseRecord] {
        let objects = try await CosUploader.listObjects(prefix: "h/", config: config)
        var keys = Set<String>()
        for obj in objects {
            // h/<roomKey>/info.json 形式（忽略 _houses.json 等历史散文件与媒体文件）
            let name = obj.name
            guard name.hasSuffix("/info.json"), !name.contains("_houses.json") else { continue }
            let parts = name.split(separator: "/").map(String.init)
            if parts.count == 3 && parts[0] == "h" && !parts[1].hasPrefix("_") { keys.insert(parts[1]) }
        }
        var records: [CloudHouseRecord] = []
        for key in keys.sorted() {
            do {
                let data = try await CosUploader.fetchObjectData(path: recordPath(roomKey: key), config: config)
                if let r = try? JSONDecoder().decode(CloudHouseRecord.self, from: data) {
                    records.append(r)
                }
            } catch let e as CosObjectNotFoundError {
                _ = e   // 该套无账本 → 跳过
            }
        }
        return records
    }

    // MARK: 从云端拉取合并（dryRun 模式返回差异明细，apply 模式执行写入）

    /// 拉取云端账本合并进本地：
    /// - 云端有、本地无 → 新建本地房源（含媒体关系）
    /// - 两边都有 → 以 updatedAt 新者为准
    /// - 云端已删除（账本无记录、本地是双端/云端态）→ 本地跟随删除（防两端不收敛）
    /// apply=false 时只算差异不写库，detail 返回确认文案
    static func pullAndMerge(houseContext: ModelContext, apply: Bool = true,
                             progress: ((Double, String) -> Void)? = nil) async -> CloudSyncResult {
        guard let config = CosConfig.load() else { return .failure("未配置云存储") }

        let cloudRecords: [CloudHouseRecord]
        do {
            cloudRecords = try await fetchAll(config: config)
        } catch {
            return .failure("无法读取云端账本：\(error.localizedDescription)")
        }

        let localHouses = (try? houseContext.fetch(FetchDescriptor<House>())) ?? []
        var localByKey: [String: House] = [:]
        for h in localHouses where h.isDeleted != true { localByKey[h.mediaRoomKey] = h }

        var addedKeys: [String] = []
        var updatedKeys: [String] = []
        var removedKeys: [String] = []
        var mediaMissing: [String] = []
        let total = max(cloudRecords.count, 1)
        var done = 0

        for record in cloudRecords {
            done += 1
            progress?(Double(done) / Double(total), "同步 \(record.roomKey)…")

            if let local = localByKey[record.roomKey] {
                // 已存在：字段级对比（v1.41 语义，不再依赖时间戳精度）
                if cloudRecordDiffers(record, from: local) {
                    updatedKeys.append(record.roomKey)
                    if apply {
                        local.roomNo = roomNoFromCloud(record.roomNo)
                        local.tower = record.tower
                        local.landlord = record.landlord
                        local.layout = record.layout
                        local.price = Double(record.price)
                        local.password = record.password
                        local.remark = record.remark
                        local.status = statusFromCloud(record.status)
                        local.lastUpdatedAt = record.updatedAt
                        local.updatedAt = record.updatedAt
                        local.updatedBy = record.updatedBy
                        local.isDeleted = false
                        local.cloudStatus = .both
                    }
                } else if apply {
                    local.cloudStatus = .both
                }
                // 媒体双向对账（v1.43 语义）：① 云端有本地缺 → 下载；② 本地有云端无 → 删记录+文件；③ 磁盘孤儿 → 删文件
                if apply {
                    reconcileMedia(record: record, house: local, houseContext: houseContext,
                                   mediaMissing: &mediaMissing)
                }
            } else {
                // 本地没有 → 新建
                addedKeys.append(record.roomKey)
                if apply {
                    let house = House(
                        roomNo: roomNoFromCloud(record.roomNo), tower: record.tower,
                        landlord: record.landlord, layout: record.layout,
                        price: Double(record.price), password: record.password,
                        remark: record.remark, status: statusFromCloud(record.status)
                    )
                    house.lastUpdatedAt = record.updatedAt
                    house.updatedAt = record.updatedAt
                    house.updatedBy = record.updatedBy
                    house.cloudStatus = .cloud
                    houseContext.insert(house)
                    reconcileMedia(record: record, house: house, houseContext: houseContext,
                                   mediaMissing: &mediaMissing)
                }
            }
            if apply { try? houseContext.save() }
        }

        // 云端已删除：本地是双端/云端态但账本无记录 → 跟随删除（与 iOS 一致；纯本地房源不删）
        for house in localHouses where house.isDeleted != true && house.isInCloud {
            if cloudRecords.contains(where: { $0.roomKey == house.mediaRoomKey }) { continue }
            removedKeys.append(house.mediaRoomKey)
            if apply {
                MediaStore.removeRoom(roomKey: house.mediaRoomKey)
                houseContext.delete(house)
            }
        }

        progress?(1.0, "完成")
        let detail = "新增 \(addedKeys.count) 套 · 更新 \(updatedKeys.count) 套 · 删除 \(removedKeys.count) 套 · 媒体补齐 \(mediaMissing.count) 个"
        return .success(added: addedKeys.count, updated: updatedKeys.count, removed: removedKeys.count, detail: detail)
    }

    /// 媒体双向对账（与 iOS v1.43 reconcile 语义一致）：
    /// ① 云端账本有、本地记录/磁盘缺 → 挂记录并标记待下载；
    /// ② 本地记录有、云端账本无 → 删记录 + 删本地文件（跟随云端删除）；
    /// ③ 磁盘上有、账本/记录均无的孤儿文件 → 只删文件（旧首帧图/分享页等残留）
    private static func reconcileMedia(record: CloudHouseRecord, house: House, houseContext: ModelContext,
                                       mediaMissing: inout [String]) {
        let cloudNorm = Set(record.mediaNames.map { mediaNormKey($0) })
        let localItems = Array(house.mediaItems)
        let localNorm = Set(localItems.map { mediaNormKey($0.fileName) })
        let diskFiles = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.roomDirectory(roomKey: house.mediaRoomKey).path)) ?? []
        let diskNorm = Set(diskFiles.map { mediaNormKey($0) })

        // ② 本地记录有、云端无 → 删除（记录 + 文件）
        for item in localItems where !cloudNorm.contains(mediaNormKey(item.fileName)) {
            MediaStore.removeMedia(fileName: item.fileName, roomKey: house.mediaRoomKey)
            houseContext.delete(item)
        }
        // ③ 磁盘孤儿（既不在账本也不在记录）→ 只删文件
        for name in diskFiles where !cloudNorm.contains(mediaNormKey(name)) && !localNorm.contains(mediaNormKey(name)) {
            try? FileManager.default.removeItem(at: MediaStore.fileURL(fileName: name, roomKey: house.mediaRoomKey))
        }
        // ① 云端有、本地缺 → 挂关系 + 标记待下载
        for name in record.mediaNames where !localNorm.contains(mediaNormKey(name)) {
            let kind = name.lowercased().hasSuffix(".mp4") || name.lowercased().hasSuffix(".mov")
                || name.lowercased().hasSuffix(".m4v") ? "video" : "image"
            house.mediaItems.append(MediaItem(fileName: name, kind: kind))
            mediaMissing.append("\(record.roomKey)/\(name)")
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
