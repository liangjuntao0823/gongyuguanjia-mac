import Foundation
import SwiftData
import SwiftUI

// MARK: - 主导航 Tab（macOS 侧边栏）

enum MainTab: String, CaseIterable, Identifiable {
    case dashboard = "工作台"
    case houses = "房源"
    case deals = "成交"
    case rents = "收租"
    case payouts = "包租"
    case profit = "汇总"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .houses: return "house"
        case .deals: return "doc.text"
        case .rents: return "banknote"
        case .payouts: return "briefcase"
        case .profit: return "chart.pie"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - 数据管理器（业务编排中枢）

@MainActor
final class DataManager: ObservableObject {

    let mainContext: ModelContext
    let houseContext: ModelContext

    @Published var selectedTab: MainTab = .dashboard

    // 双 store 数据（View 不直接 @Query，统一从这里读取，避免 SwiftData 多配置路由问题）
    @Published var houses: [House] = []
    @Published var deals: [DealRecord] = []
    @Published var payouts: [PayoutRecord] = []
    @Published var properties: [Property] = []

    init(mainContext: ModelContext, houseContext: ModelContext) {
        self.mainContext = mainContext
        self.houseContext = houseContext
        NetworkMonitor.start()
        LocalNotificationManager.requestAuthorization()
        refreshAll()
        NotificationCenter.default.addObserver(forName: .macHouseChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshHouses() }
        }
        NotificationCenter.default.addObserver(forName: .macDataChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshData() }
        }
    }

    // MARK: - 数据加载

    func refreshAll() {
        refreshHouses()
        refreshData()
    }

    func refreshHouses() {
        let fd = FetchDescriptor<House>()
        houses = (try? houseContext.fetch(fd)) ?? []
    }

    func refreshData() {
        deals = (try? mainContext.fetch(FetchDescriptor<DealRecord>())) ?? []
        payouts = (try? mainContext.fetch(FetchDescriptor<PayoutRecord>())) ?? []
        properties = (try? mainContext.fetch(FetchDescriptor<Property>())) ?? []
    }

    // MARK: - 房源 CRUD

    /// 新增房源：插入 + 自动上传媒体 + 自动生成脱敏 H5（v1.55：新增即生成）
    func addHouse(roomNo: String, tower: Int, landlord: String, layout: String,
                  price: Double, password: String, remark: String, status: String,
                  mediaFiles: [(url: URL, kind: String)] = []) -> House {
        let house = House(roomNo: roomNo, tower: tower, landlord: landlord, layout: layout,
                          price: price, password: password, remark: remark, status: status)
        houseContext.insert(house)
        for (url, kind) in mediaFiles {
            let fileName = house.mediaRoomKey + "_" + UUID().uuidString.prefix(8) + "_" + url.lastPathComponent
            if let data = try? Data(contentsOf: url) {
                MediaStore.save(data: data, fileName: fileName, roomKey: house.mediaRoomKey)
            }
            house.mediaItems.append(MediaItem(fileName: fileName, kind: kind))
            // 上传队列（云端）
            HouseMediaUploadQueue.shared.enqueue(roomKey: house.mediaRoomKey, fileName: fileName, kind: kind)
        }
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        // 自动生成脱敏 H5
        autoRegenerateMaskedShare(for: house)
        return house
    }

    /// 更新房源：改字段 + 媒体增删 + 重生成 H5（删旧生成新）
    func updateHouse(_ house: House, roomNo: String, tower: Int, landlord: String, layout: String,
                     price: Double, password: String, remark: String, status: String) {
        house.roomNo = roomNo
        house.tower = tower
        house.landlord = landlord
        house.layout = layout
        house.price = price
        house.password = password
        house.remark = remark
        house.status = status
        house.updatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        autoRegenerateMaskedShare(for: house)
    }

    /// 添加媒体到房源
    func addMedia(to house: House, url: URL, kind: String) {
        let fileName = house.mediaRoomKey + "_" + UUID().uuidString.prefix(8) + "_" + url.lastPathComponent
        if let data = try? Data(contentsOf: url) {
            MediaStore.save(data: data, fileName: fileName, roomKey: house.mediaRoomKey)
        }
        house.mediaItems.append(MediaItem(fileName: fileName, kind: kind))
        house.updatedAt = Date()
        try? houseContext.save()
        HouseMediaUploadQueue.shared.enqueue(roomKey: house.mediaRoomKey, fileName: fileName, kind: kind)
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
    }

    /// 删除媒体（本地 + 云端）
    func removeMedia(_ item: MediaItem, from house: House) {
        MediaStore.removeMedia(fileName: item.fileName, roomKey: house.mediaRoomKey)
        houseContext.delete(item)
        house.updatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        // 云端删除（后台）
        if let config = CosConfig.load() {
            Task {
                let remoteName = item.kind == "video" ? CosUploader.cloudVideoName(for: item.fileName) : item.fileName
                try? await CosUploader.deleteObject(path: "h/\(house.mediaRoomKey)/\(remoteName)", config: config)
            }
        }
        autoRegenerateMaskedShare(for: house)
    }

    /// 软删除房源（回收站）
    func softDeleteHouse(_ house: House) {
        house.isDeleted = true
        house.deletedAt = Date()
        house.updatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
    }

    /// 恢复回收站房源
    func restoreHouse(_ house: House) {
        house.isDeleted = false
        house.deletedAt = nil
        house.updatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        autoRegenerateMaskedShare(for: house)
    }

    /// 彻底删除房源（本地媒体 + 云端 h/<roomKey>/ + 分享页 + 账本条目）
    func permanentDeleteHouse(_ house: House) {
        let roomKey = house.mediaRoomKey
        // 删本地媒体
        MediaStore.removeRoom(roomKey: roomKey)
        // 删云端（后台）
        if let config = CosConfig.load() {
            Task {
                try? await CosUploader.deleteObject(path: "h/\(roomKey)", config: config)
                try? await CosUploader.deleteObject(path: "\(CloudUser.sharePagePrefix)\(roomKey)", config: config)
            }
        }
        houseContext.delete(house)
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
    }

    // MARK: - 自动生成/重生成脱敏 H5（v1.55：新增/编辑即生成，防选房链接打不开）

    func autoRegenerateMaskedShare(for house: House) {
        guard CosConfig.load() != nil, !house.mediaItems.isEmpty else { return }
        let info = shareInfo(for: house)
        let mediaFiles = house.mediaItems.map { ShareMediaFile(name: $0.fileName, kind: $0.kind) }
        Task {
            do {
                _ = try await CosUploader.shareCard(
                    mediaFiles: mediaFiles, roomKey: house.mediaRoomKey,
                    info: info, mode: .masked, config: CosConfig.load()!
                )
            } catch {
                CrashLogCollector.record("自动生成分享页失败", detail: "\(house.mediaRoomKey): \(error.localizedDescription)")
            }
        }
    }

    func shareInfo(for house: House) -> ShareHouseInfo {
        ShareHouseInfo(
            displayRoomNo: house.displayRoomNo,
            towerLabel: house.towerLabel,
            layout: house.layout,
            statusLabel: house.status,
            priceText: "\(Int(house.price))元",
            landlord: house.landlord,
            password: house.password,
            remark: house.remark,
            name: ShareNameStore.displayName,
            phone: ShareNameStore.displayPhone
        )
    }

    // MARK: - 经营数据 CRUD

    func addDeal(_ record: DealRecord) {
        mainContext.insert(record)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func updateDeal(_ record: DealRecord, roomNo: String, dealDate: Date, dealType: String,
                    price: Double, commission: Double, fee: Double, paidBy: String, remark: String) {
        record.roomNo = roomNo
        record.dealDate = dealDate
        record.dealType = dealType
        record.price = price
        record.commission = commission
        record.fee = fee
        record.paidBy = paidBy
        record.remark = remark
        record.updatedAt = Date()
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func deleteDeal(_ record: DealRecord) {
        mainContext.delete(record)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func addPayout(_ record: PayoutRecord) {
        mainContext.insert(record)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func updatePayout(_ record: PayoutRecord, amount: Double, category: String, date: Date, remark: String) {
        record.amount = amount
        record.category = category
        record.date = date
        record.remark = remark
        record.updatedAt = Date()
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func deletePayout(_ record: PayoutRecord) {
        mainContext.delete(record)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func addProperty(_ property: Property) {
        mainContext.insert(property)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func updateProperty(_ property: Property, name: String, address: String,
                        monthlyRent: Double, monthlyExpense: Double, remark: String) {
        property.name = name
        property.address = address
        property.monthlyRent = monthlyRent
        property.monthlyExpense = monthlyExpense
        property.remark = remark
        property.updatedAt = Date()
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func deleteProperty(_ property: Property) {
        mainContext.delete(property)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    // MARK: - 云端同步

    func syncFromCloud() async -> CloudSyncResult {
        let result = await CloudHouseSync.pullAndMerge(houseContext: houseContext)
        if case .success(let added, let updated, _) = result {
            // 下载缺失媒体
            let houses = (try? houseContext.fetch(FetchDescriptor<House>())) ?? []
            if let config = CosConfig.load() {
                for h in houses where h.isDeleted != true {
                    await CloudHouseSync.downloadMissingMedia(house: h, config: config)
                }
            }
            BackupLogStore.log("云端同步", detail: "新增\(added) 更新\(updated)", kind: "sync")
            return result
        }
        if case .failure(let msg) = result {
            BackupLogStore.log("云端同步失败", detail: msg, kind: "sync")
        }
        return result
    }

    func pushToCloud() async -> CloudSyncResult {
        let result = await CloudHouseSync.pushAll(houseContext: houseContext)
        if case .success(let added, _, _) = result {
            BackupLogStore.log("房源上传云端", detail: "共 \(added) 套", kind: "sync")
        }
        return result
    }

    // MARK: - 统计

    struct HouseStats {
        var total = 0
        var available = 0
        var rented = 0
        var tower1 = 0
        var tower2 = 0
        var withPhoto = 0
        var withoutPhoto = 0
        var totalMonthlyRent: Double = 0
    }

    func houseStats(_ houses: [House]) -> HouseStats {
        var s = HouseStats()
        for h in houses where h.isDeleted != true {
            s.total += 1
            if h.isAvailable { s.available += 1 } else { s.rented += 1 }
            if h.tower == 1 { s.tower1 += 1 } else { s.tower2 += 1 }
            if h.hasRealPhoto { s.withPhoto += 1 } else { s.withoutPhoto += 1 }
            if h.isAvailable { s.totalMonthlyRent += h.price }
        }
        return s
    }

    // MARK: - 收租/到期计算

    /// 生成某房源的下一次收租日（按成交日期月周期）
    static func nextRentDate(after dealDate: Date, months: Int = 1) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: dealDate) ?? dealDate
    }
}
