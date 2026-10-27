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
        var localExtra: [String: [String]] = [:]   // roomKey → 本地有、云端账本缺的媒体名
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
                // 媒体双向对账（v1.43 + v1.65 语义）：① 云端有本地缺 → 下载；② 本地有云端账本无 → 暂存，同步后查云端对象决定删/补账本；③ 磁盘孤儿 → 删文件
                if apply {
                    reconcileMedia(record: record, house: local, houseContext: houseContext,
                                   mediaMissing: &mediaMissing, localExtra: &localExtra)
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
                                   mediaMissing: &mediaMissing, localExtra: &localExtra)
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

        // 无变化媒体对账（v1.65/v1.68 语义）：本地有、云端账本缺的媒体 → 查云端对象
        //   · 对象存在 → 补写云端账本（补传账本 mediaNames）
        //   · 对象不存在 → 删除本地记录 + 文件（跟随删），有本地文件则先补传对象再补账本
        var reconciled = 0
        var reuploaded = 0
        if apply && !localExtra.isEmpty, let cfg = CosConfig.load() {
            for (roomKey, names) in localExtra {
                let objs = (try? await CosUploader.listObjects(prefix: "h/\(roomKey)/", config: cfg)) ?? []
                let objNorms = Set(objs.map { mediaNormKey(URL(string: "x://\($0.name)")?.lastPathComponent ?? $0.name) })
                for name in names {
                    let norm = mediaNormKey(name)
                    let localURL = MediaStore.fileURL(fileName: name, roomKey: roomKey)
                    if objNorms.contains(norm) {
                        // 云端对象在 → 补账本
                        if let house = localByKey[roomKey] {
                            do { try await saveRecord(record(from: house), config: cfg); reconciled += 1 }
                            catch { CrashLogCollector.record("媒体对账补账本失败", detail: "\(roomKey)/\(name)") }
                        }
                    } else if FileManager.default.fileExists(atPath: localURL.path) {
                        // 对象不在但有本地文件 → 补传对象（入队自动上传）
                        let kind = name.lowercased().hasSuffix(".mp4") || name.lowercased().hasSuffix(".mov") || name.lowercased().hasSuffix(".m4v") ? "video" : "image"
                        await HouseMediaUploadQueue.shared.enqueue(roomKey: roomKey, fileName: name, kind: kind)
                        reuploaded += 1
                    } else {
                        // 云端对象与本地文件都不在 → 删记录
                        if let house = localByKey[roomKey], let item = house.mediaItems.first(where: { mediaNormKey($0.fileName) == norm }) {
                            MediaStore.removeMedia(fileName: item.fileName, roomKey: roomKey)
                            houseContext.delete(item)
                        }
                    }
                }
            }
            try? houseContext.save()
        }

        progress?(1.0, "完成")
        let extraNote = (reconciled > 0 || reuploaded > 0) ? " · 账本补齐 \(reconciled) 项 · 媒体补传 \(reuploaded) 个" : ""
        let detail = "新增 \(addedKeys.count) 套 · 更新 \(updatedKeys.count) 套 · 删除 \(removedKeys.count) 套 · 媒体补齐 \(mediaMissing.count) 个\(extraNote)"
        return .success(added: addedKeys.count, updated: updatedKeys.count, removed: removedKeys.count, detail: detail)
    }

    /// 媒体双向对账（与 iOS v1.43 reconcile 语义一致）：
    /// ① 云端账本有、本地记录/磁盘缺 → 挂记录并标记待下载；
    /// ② 本地记录有、云端账本无 → 删记录 + 删本地文件（跟随云端删除）；
    /// ③ 磁盘上有、账本/记录均无的孤儿文件 → 只删文件（旧首帧图/分享页等残留）
    private static func reconcileMedia(record: CloudHouseRecord, house: House, houseContext: ModelContext,
                                       mediaMissing: inout [String], localExtra: inout [String: [String]]) {
        let cloudNorm = Set(record.mediaNames.map { mediaNormKey($0) })
        let localItems = Array(house.mediaItems)
        let localNorm = Set(localItems.map { mediaNormKey($0.fileName) })
        let diskFiles = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.roomDirectory(roomKey: house.mediaRoomKey).path)) ?? []
        let diskNorm = Set(diskFiles.map { mediaNormKey($0) })

        // ② 本地记录有、云端账本无 → 不立即删，收集后由同步尾部查云端对象决定（删 / 补账本 / 补传）
        for item in localItems where !cloudNorm.contains(mediaNormKey(item.fileName)) {
            let k = house.mediaRoomKey
            localExtra[k, default: []].append(item.fileName)
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

// MARK: - 无前缀媒体目录自动迁移（对齐 iOS v1.69：1 座/2 座目录统一带前缀）

extension CloudHouseSync {
    /// 扫描 media 根目录下不带 1-/2- 前缀的房源目录，按本地房源匹配归属座后重命名。
    /// 幂等：返回迁移目录数；无可迁移或全部带前缀时返回 0。
    static func migrateUnprefixedHouseDirectories(houseContext: ModelContext) -> Int {
        guard let houses = try? houseContext.fetch(FetchDescriptor<House>()) else { return 0 }
        let active = houses.filter { $0.isDeleted != true }
        let names = MediaStore.scanMediaDirectoryKeys()
        var migrated = 0
        for dirName in names {
            if dirName.hasPrefix("1-") || dirName.hasPrefix("2-") { continue }   // 已带前缀
            // 无前缀目录：找房号与之完全一致的房源确定座号
            guard let h = active.first(where: { $0.roomNo == dirName }) else { continue }
            let target = "\(h.tower)-\(dirName)"
            if target == dirName { continue }
            let from = MediaStore.mediaDirectory().appendingPathComponent(dirName)
            let to = MediaStore.mediaDirectory().appendingPathComponent(target)
            do {
                try FileManager.default.moveItem(at: from, to: to)
                migrated += 1
            } catch {
                CrashLogCollector.record("媒体目录迁移失败", detail: "\(dirName) → \(target): \(error.localizedDescription)")
            }
        }
        return migrated
    }
}

// MARK: - 本地房源账本镜像（对齐 iOS v1.72/v1.75/v1.77）

/// 与云端同构：每套房在 media/<房号>/info.json 存一份 CloudHouseRecord。
/// 效果：本地「一房一账本」，删除整套 = 删 media/<房号>/（媒体+账本一步到位）；
/// 备份/恢复/对账时本地账本与云端结构完全一致；支持离线重建房源。
enum LocalHouseLedger {

    /// 写本套账本（幂等覆盖）
    static func save(_ house: House) {
        let record = CloudHouseSync.record(from: house)
        let dir = MediaStore.houseDirectory(roomKey: house.mediaRoomKey)
        let url = dir.appendingPathComponent("info.json")
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 删本套账本（媒体目录删除时一并清理；单独调用用于软删后彻底清理）
    static func delete(roomKey: String) {
        let url = MediaStore.houseDirectory(roomKey: roomKey).appendingPathComponent("info.json")
        try? FileManager.default.removeItem(at: url)
    }

    /// 重建/刷新全部本地账本镜像（对齐 iOS v1.76 语义，仅云端同步后调用）：
    /// 对本地未删除房源逐套与现有账本做语义字段对比，有差异才写盘。
    /// 返回实际写入套数。
    static func rebuildAll(houseContext: ModelContext) -> Int {
        guard let houses = try? houseContext.fetch(FetchDescriptor<House>()) else { return 0 }
        var written = 0
        for house in houses where house.isDeleted != true {
            let url = MediaStore.houseDirectory(roomKey: house.mediaRoomKey).appendingPathComponent("info.json")
            if let data = try? Data(contentsOf: url),
               let rec = try? JSONDecoder().decode(CloudHouseRecord.self, from: data),
               !CloudHouseSync.cloudRecordDiffers(rec, from: house) {
                continue  // 无差异，零写入
            }
            save(house)
            written += 1
        }
        return written
    }

    /// 离线一键重建（对齐 iOS v1.75）：扫描本地 media/<房号>/info.json，
    /// 按账本「刷新+补齐」本地房源。幂等合并：已有房源按账本覆盖字段与媒体清单，
    /// 缺失房源新建；不删除任何现有数据。无需联网。返回处理房源套数。
    static func restoreAll(houseContext: ModelContext) -> Int {
        let dir = MediaStore.mediaDirectory()
        guard let roomDirs = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var localByKey: [String: House] = [:]
        if let all = try? houseContext.fetch(FetchDescriptor<House>()) {
            for h in all where h.isDeleted != true { localByKey[h.mediaRoomKey] = h }
        }
        var restored = 0
        for roomDirName in roomDirs {
            if roomDirName.hasPrefix(".") { continue }
            let ledgerURL = dir.appendingPathComponent(roomDirName).appendingPathComponent("info.json")
            guard let data = try? Data(contentsOf: ledgerURL),
                  let rec = try? JSONDecoder().decode(CloudHouseRecord.self, from: data) else { continue }
            let house: House
            if let h = localByKey[rec.roomKey] {
                h.roomNo = rec.roomNo; h.tower = rec.tower; h.landlord = rec.landlord
                h.layout = rec.layout; h.price = Double(rec.price); h.password = rec.password
                h.remark = rec.remark; h.statusRaw = CloudHouseSync.statusFromCloud(rec.status)
                h.lastUpdatedAt = rec.updatedAt
                house = h
            } else {
                let h = House(roomNo: rec.roomNo, tower: rec.tower, landlord: rec.landlord,
                              layout: rec.layout, price: Double(rec.price), password: rec.password,
                              remark: rec.remark, status: CloudHouseSync.statusFromCloud(rec.status))
                h.lastUpdatedAt = rec.updatedAt
                h.cloudStatusRaw = "local"
                houseContext.insert(h)
                house = h
            }
            // 媒体清单以账本为准：缺的补建记录、账本没有的移除记录（磁盘媒体文件不动）
            let cloudNames = Set(rec.mediaNames)
            let existing = Set(house.mediaItems.map { $0.fileName })
            for name in rec.mediaNames where !existing.contains(name) {
                let lower = name.lowercased()
                let kind = (lower.hasSuffix(".mp4") || lower.hasSuffix(".mov")) ? "video" : "image"
                let item = MediaItem(fileName: name, kind: kind)
                item.house = house
                houseContext.insert(item)
            }
            for item in Array(house.mediaItems) where !cloudNames.contains(item.fileName) {
                houseContext.delete(item)
            }
            restored += 1
        }
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        return restored
    }
}
