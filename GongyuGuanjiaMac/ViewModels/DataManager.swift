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

// MARK: - 数据管理器（业务编排中枢，Mac 版 View 统一从这里读取，避免 SwiftData 多配置路由问题）

@MainActor
final class DataManager: ObservableObject {

    let mainContext: ModelContext
    let houseContext: ModelContext

    @Published var selectedTab: MainTab = .dashboard

    // 经营数据（main 容器）
    @Published var deals: [DealRecord] = []
    @Published var payouts: [PayoutRecord] = []
    @Published var properties: [Property] = []
    @Published var todos: [TodoItem] = []
    @Published var miscIncomes: [MiscIncome] = []
    @Published var miscExpenses: [MiscExpense] = []
    @Published var profitCalculations: [ProfitCalculation] = []
    @Published var utilityHistories: [UtilitySettlementHistory] = []

    // 房源数据（house 容器）
    @Published var houses: [House] = []

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
        houses = (try? houseContext.fetch(FetchDescriptor<House>())) ?? []
    }

    func refreshData() {
        deals = (try? mainContext.fetch(FetchDescriptor<DealRecord>())) ?? []
        payouts = (try? mainContext.fetch(FetchDescriptor<PayoutRecord>())) ?? []
        properties = (try? mainContext.fetch(FetchDescriptor<Property>())) ?? []
        todos = (try? mainContext.fetch(FetchDescriptor<TodoItem>())) ?? []
        miscIncomes = (try? mainContext.fetch(FetchDescriptor<MiscIncome>())) ?? []
        miscExpenses = (try? mainContext.fetch(FetchDescriptor<MiscExpense>())) ?? []
        profitCalculations = (try? mainContext.fetch(FetchDescriptor<ProfitCalculation>())) ?? []
        utilityHistories = (try? mainContext.fetch(FetchDescriptor<UtilitySettlementHistory>())) ?? []
    }

    // MARK: - 媒体命名（与 iOS 对齐：roomKey-TAG-uid-N.ext，防双端拉取互删关系）

    /// 生成 iOS 同款媒体文件名：\(roomKey)-\(TAG)-\(uid8)-\(n).\(ext)
    static func makeMediaFileName(roomKey: String, sourceName: String, kind: String, usedNames: Set<String>) -> String {
        let ext = (sourceName as NSString).pathExtension.lowercased()
        let tag: String
        switch ext {
        case "png": tag = "PNG"
        case "heic": tag = "HEIC"
        case "gif": tag = "GIF"
        case "mp4", "mov", "m4v": tag = "MP4"
        default: tag = "JPG"
        }
        let uid = String(UUID().uuidString.prefix(8)).uppercased()
        var n = 1
        var name = "\(roomKey)-\(tag)-\(uid)-\(n).\(ext)"
        while usedNames.contains(name) {
            n += 1
            name = "\(roomKey)-\(tag)-\(uid)-\(n).\(ext)"
        }
        return name
    }

    // MARK: - 房源 CRUD（house 容器）

    /// 新增房源：插入 + 自动上传媒体 + 自动生成脱敏 H5（新增即生成）
    func addHouse(roomNo: String, tower: Int, landlord: String, layout: String,
                  price: Double, password: String, remark: String, status: String,
                  mediaFiles: [(url: URL, kind: String)] = []) -> House {
        let house = House(roomNo: roomNo, tower: tower, landlord: landlord, layout: layout,
                          price: price, password: password, remark: remark, status: status)
        houseContext.insert(house)
        var usedNames = Set(house.mediaItems.map { $0.fileName })
        for (url, kind) in mediaFiles {
            let fileName = Self.makeMediaFileName(roomKey: house.mediaRoomKey, sourceName: url.lastPathComponent, kind: kind, usedNames: usedNames)
            usedNames.insert(fileName)
            if let data = try? Data(contentsOf: url) {
                MediaStore.save(data: data, fileName: fileName, roomKey: house.mediaRoomKey)
            }
            house.mediaItems.append(MediaItem(fileName: fileName, kind: kind))
            Task { await HouseMediaUploadQueue.shared.enqueue(roomKey: house.mediaRoomKey, fileName: fileName, kind: kind) }
        }
        house.lastUpdatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        pushHouseLedgerIfConfigured(house)
        LocalHouseLedger.save(house)   // 本地账本镜像：media/<房号>/info.json
        autoRegenerateMaskedShare(for: house)
        CloudOps.log(category: "房源", action: "新增", result: "成功", detail: "\(house.displayRoomNo) · 媒体 \(mediaFiles.count) 个", room: house.mediaRoomKey)
        return house
    }

    /// 保存后推送单套账本到云端（对齐 iOS uploadOne：字段/媒体变化即时同步）
    private func pushHouseLedgerIfConfigured(_ house: House) {
        guard let config = CosConfig.load(), config.isValid else { return }
        let record = CloudHouseSync.record(from: house)
        Task { try? await CloudHouseSync.saveRecord(record, config: config) }
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
        house.lastUpdatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        pushHouseLedgerIfConfigured(house)
        LocalHouseLedger.save(house)   // 本地账本镜像随更新同步
        autoRegenerateMaskedShare(for: house)
        CloudOps.log(category: "房源", action: "更新", result: "成功", detail: "\(house.displayRoomNo)", room: house.mediaRoomKey)
    }

    func addMedia(to house: House, url: URL, kind: String) {
        var usedNames = Set(house.mediaItems.map { $0.fileName })
        let fileName = Self.makeMediaFileName(roomKey: house.mediaRoomKey, sourceName: url.lastPathComponent, kind: kind, usedNames: usedNames)
        usedNames.insert(fileName)
        if let data = try? Data(contentsOf: url) {
            MediaStore.save(data: data, fileName: fileName, roomKey: house.mediaRoomKey)
        }
        house.mediaItems.append(MediaItem(fileName: fileName, kind: kind))
        house.updatedAt = Date()
        house.lastUpdatedAt = Date()
        try? houseContext.save()
        Task { await HouseMediaUploadQueue.shared.enqueue(roomKey: house.mediaRoomKey, fileName: fileName, kind: kind) }
        pushHouseLedgerIfConfigured(house)
        LocalHouseLedger.save(house)   // 本地账本镜像随媒体新增更新
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
    }

    func removeMedia(_ item: MediaItem, from house: House) {
        MediaStore.removeMedia(fileName: item.fileName, roomKey: house.mediaRoomKey)
        pushHouseLedgerIfConfigured(house)
        LocalHouseLedger.save(house)   // 本地账本镜像随媒体删除更新
        houseContext.delete(item)
        house.updatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        if let config = CosConfig.load() {
            Task {
                let remoteName = item.kind == "video" ? CosUploader.cloudVideoName(for: item.fileName) : item.fileName
                try? await CosUploader.deleteObject(path: "h/\(house.mediaRoomKey)/\(remoteName)", config: config)
            }
        }
        autoRegenerateMaskedShare(for: house)
        CloudOps.log(category: "房源", action: "删媒体", result: "成功", detail: "\(house.displayRoomNo) · \(item.fileName)", room: house.mediaRoomKey)
    }

    func softDeleteHouse(_ house: House) {
        house.isDeleted = true
        house.deletedAt = Date()
        house.updatedAt = Date()
        house.lastUpdatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        LocalHouseLedger.delete(roomKey: house.mediaRoomKey)   // 本地账本镜像随软删清理
        // 云端账本同步删除（媒体目录与 H5 保留，还原不丢图；iOS 端下次同步即消失）
        if let config = CosConfig.load(), config.isValid {
            Task {
                _ = try? await CosUploader.deleteObject(path: CloudHouseSync.recordPath(roomKey: house.mediaRoomKey), config: config)
            }
        }
        CloudOps.log(category: "房源", action: "删除", result: "成功", detail: "\(house.displayRoomNo) · 媒体 \(house.mediaItems.count) 个", room: house.mediaRoomKey)
    }

    func restoreHouse(_ house: House) {
        house.isDeleted = false
        house.deletedAt = nil
        house.updatedAt = Date()
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        autoRegenerateMaskedShare(for: house)
    }

    func permanentDeleteHouse(_ house: House) {
        let roomKey = house.mediaRoomKey
        MediaStore.removeRoom(roomKey: roomKey)
        // 云端完整删除（对齐 iOS v1.69：删桶目录全部对象 + 账本 + 分享页；失败不阻塞本地，写日志提示）
        if let config = CosConfig.load(), config.isValid {
            Task {
                do {
                    let objects = try await CosUploader.listObjects(prefix: "h/\(roomKey)/", config: config)
                    for obj in objects {
                        try? await CosUploader.deleteObject(path: obj.name, config: config)
                    }
                    try? await CosUploader.deleteObject(path: CloudHouseSync.recordPath(roomKey: roomKey), config: config)
                    try? await CosUploader.deleteObject(path: "\(CloudUser.sharePagePrefix)\(roomKey)", config: config)
                    CloudOps.log(category: "房源", action: "彻底删除（本地+云端）", result: "成功",
                                 detail: "\(house.displayRoomNo) · 云端桶 \(objects.count) 个对象 + 账本", room: roomKey)
                } catch {
                    CloudOps.log(category: "房源", action: "彻底删除（本地+云端）", result: "失败",
                                 detail: "\(house.displayRoomNo) \(error.localizedDescription)。可手动清理 h/\(roomKey)/", room: roomKey)
                }
            }
        } else {
            CloudOps.log(category: "房源", action: "彻底删除", result: "成功", detail: "\(house.displayRoomNo)（未配置云存储，仅本地）", room: roomKey)
        }
        houseContext.delete(house)
        try? houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        CloudOps.log(category: "房源", action: "彻底删除", result: "成功", detail: "\(roomKey)", room: roomKey)
    }

    // MARK: - 自动生成/重生成脱敏 H5

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

    // MARK: - 成交合同 CRUD（对齐 iOS 契约）

    func addDeal(date: Date = Date(), roomNumber: String = "", landlord: String = "", unitType: String = "",
                 leaseStart: Date = Date(), leaseEnd: Date = Date(), leaseDuration: String = "",
                 rent: Double = 0, deposit: Double = 0, prepayment: Double = 0, rentDueDay: Int? = nil,
                 agentFeeLandlord: Double = 0, agentFeeTenant: Double = 0, totalFee: Double = 0,
                 manager: String = "", source: String = "", notes: String = "") -> DealRecord {
        let record = DealRecord(date: date, roomNumber: roomNumber, landlord: landlord, unitType: unitType,
                                leaseStart: leaseStart, leaseEnd: leaseEnd, leaseDuration: leaseDuration,
                                rent: rent, deposit: deposit, prepayment: prepayment, rentDueDay: rentDueDay,
                                agentFeeLandlord: agentFeeLandlord, agentFeeTenant: agentFeeTenant,
                                totalFee: totalFee, manager: manager, source: source, notes: notes)
        mainContext.insert(record)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
        return record
    }

    func softDeleteDeal(_ record: DealRecord) {
        record.isDeleted = true
        record.deletedAt = Date()
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func restoreDeal(_ record: DealRecord) {
        record.isDeleted = false
        record.deletedAt = nil
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func permanentDeleteDeal(_ record: DealRecord) {
        mainContext.delete(record)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    // MARK: - 包租合同 CRUD（对齐 iOS 契约）

    func addPayout(roomNumber: String = "", manager: String = "", unitType: String = "",
                   leaseStartDate: Date = Date(), leaseEndDate: Date = Date(), leaseDuration: String = "",
                   rentFreeDays: Int = 0, monthlyRent: Double? = nil, annualRent: Double = 0,
                   deposit: Double = 0, waterMeterBase: Int = 0, electricMeterBase: Int = 0,
                   rentDueDay: Int = 1, paymentMethod: String = "月付", notes: String = "") -> PayoutRecord {
        let record = PayoutRecord(roomNumber: roomNumber, manager: manager, unitType: unitType,
                                  leaseStartDate: leaseStartDate, leaseEndDate: leaseEndDate,
                                  leaseDuration: leaseDuration, rentFreeDays: rentFreeDays,
                                  monthlyRent: monthlyRent, annualRent: annualRent, deposit: deposit,
                                  waterMeterBase: waterMeterBase, electricMeterBase: electricMeterBase,
                                  rentDueDay: rentDueDay, paymentMethod: paymentMethod, notes: notes)
        mainContext.insert(record)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
        return record
    }

    func softDeletePayout(_ record: PayoutRecord) {
        record.isDeleted = true
        record.deletedAt = Date()
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func restorePayout(_ record: PayoutRecord) {
        record.isDeleted = false
        record.deletedAt = nil
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func permanentDeletePayout(_ record: PayoutRecord) {
        mainContext.delete(record)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    // MARK: - 收租房源 CRUD（对齐 iOS 契约）

    func addProperty(roomNumber: String = "", landlord: String = "", unitType: String = "",
                     rent: Double = 0, deposit: Double = 0, prepayment: Double = 0,
                     leaseStart: String = "", leaseEnd: String = "", leaseDuration: String = "",
                     rentDueDay: Int = 1, waterMeterBase: Int = 0, electricMeterBase: Int = 0,
                     propertyType: String = "管理", notes: String = "") -> Property {
        let prop = Property(roomNumber: roomNumber, landlord: landlord, unitType: unitType,
                            rent: rent, deposit: deposit, prepayment: prepayment,
                            leaseStart: leaseStart, leaseEnd: leaseEnd, leaseDuration: leaseDuration,
                            rentDueDay: rentDueDay, waterMeterBase: waterMeterBase,
                            electricMeterBase: electricMeterBase, propertyType: propertyType, notes: notes)
        mainContext.insert(prop)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
        return prop
    }

    func softDeleteProperty(_ prop: Property) {
        prop.isDeleted = true
        prop.deletedAt = Date()
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func restoreProperty(_ prop: Property) {
        prop.isDeleted = false
        prop.deletedAt = nil
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func permanentDeleteProperty(_ prop: Property) {
        mainContext.delete(prop)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    /// 退租：写入终止信息并标记
    func terminateProperty(_ prop: Property, date: Date?, reason: String,
                           depositRefund: String, roomDamage: String,
                           utilitySettlement: String, person: String, phone: String) {
        prop.isTerminated = true
        prop.terminationDate = date
        prop.terminationReason = reason
        prop.depositRefundStatus = depositRefund
        prop.roomDamageStatus = roomDamage
        prop.utilitySettlementStatus = utilitySettlement
        prop.terminationPerson = person
        prop.terminationPhone = phone
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    /// 还原退租
    func restoreTerminatedProperty(_ prop: Property) {
        prop.isTerminated = false
        prop.terminationDate = nil
        prop.terminationReason = ""
        prop.depositRefundStatus = ""
        prop.roomDamageStatus = ""
        prop.utilitySettlementStatus = ""
        prop.terminationPerson = ""
        prop.terminationPhone = ""
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    // MARK: - 杂项收支 CRUD

    func addMiscIncome(date: Date = Date(), item: String = "", amount: Double = 0, notes: String = "") {
        let rec = MiscIncome(date: date, item: item, amount: amount, notes: notes)
        mainContext.insert(rec)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func addMiscExpense(date: Date = Date(), item: String = "", amount: Double = 0, notes: String = "") {
        let rec = MiscExpense(date: date, item: item, amount: amount, notes: notes)
        mainContext.insert(rec)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func softDeleteMiscIncome(_ rec: MiscIncome) {
        rec.isDeleted = true
        rec.deletedAt = Date()
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func softDeleteMiscExpense(_ rec: MiscExpense) {
        rec.isDeleted = true
        rec.deletedAt = Date()
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func restoreMiscIncome(_ rec: MiscIncome) {
        rec.isDeleted = false
        rec.deletedAt = nil
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func restoreMiscExpense(_ rec: MiscExpense) {
        rec.isDeleted = false
        rec.deletedAt = nil
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func permanentDeleteMiscIncome(_ rec: MiscIncome) {
        mainContext.delete(rec)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func permanentDeleteMiscExpense(_ rec: MiscExpense) {
        mainContext.delete(rec)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    // MARK: - 利润测算 CRUD

    func addProfitCalculation(_ calc: ProfitCalculation) {
        mainContext.insert(calc)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func deleteProfitCalculation(_ calc: ProfitCalculation) {
        mainContext.delete(calc)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    // MARK: - 待办 CRUD（SwiftData 模型版）

    func addTodo(content: String, reminderDate: Date? = nil) {
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let item = TodoItem(content: content, sortOrder: todos.count, reminderDate: reminderDate)
        mainContext.insert(item)
        try? mainContext.save()
        LocalNotificationManager.rebuildTodoReminders(todos: allTodos)
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func updateTodo(_ item: TodoItem, content: String, createdDate: Date? = nil, reminderDate: Date? = nil) {
        item.content = content
        if let createdDate { item.createdDate = createdDate }
        if let reminderDate { item.reminderDate = reminderDate }
        try? mainContext.save()
        LocalNotificationManager.rebuildTodoReminders(todos: allTodos)
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    /// 全部待办（含已删除，供回收站）
    var allTodos: [TodoItem] {
        (try? mainContext.fetch(FetchDescriptor<TodoItem>())) ?? []
    }

    func toggleTodo(_ item: TodoItem) {
        item.isCompleted.toggle()
        item.completedDate = item.isCompleted ? Date() : nil
        try? mainContext.save()
        LocalNotificationManager.rebuildTodoReminders(todos: allTodos)
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func softDeleteTodo(_ item: TodoItem) {
        item.isDeleted = true
        item.deletedAt = Date()
        try? mainContext.save()
        LocalNotificationManager.rebuildTodoReminders(todos: allTodos)
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func restoreTodo(_ item: TodoItem) {
        item.isDeleted = false
        item.deletedAt = nil
        try? mainContext.save()
        LocalNotificationManager.rebuildTodoReminders(todos: allTodos)
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    func permanentDeleteTodo(_ item: TodoItem) {
        mainContext.delete(item)
        try? mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }

    // MARK: - 云端同步

    func syncFromCloud(progress: ((Double, String) -> Void)? = nil) async -> CloudSyncResult {
        let result = await CloudHouseSync.pullAndMerge(houseContext: houseContext, apply: true, progress: progress)
        if case .success(let added, let updated, let removed, let detail) = result {
            let houses = (try? houseContext.fetch(FetchDescriptor<House>())) ?? []
            if let config = CosConfig.load() {
                for h in houses where h.isDeleted != true {
                    await CloudHouseSync.downloadMissingMedia(house: h, config: config)
                }
            }
            LocalHouseLedger.rebuildAll(houseContext: houseContext)   // 同步后重建本地账本镜像（v1.77）
            BackupLogStore.log("云端同步", detail: detail, kind: "sync")
            CloudOps.log(category: "同步", action: "拉取", result: "成功", detail: detail)
            return .success(added: added, updated: updated, removed: removed, detail: detail)
        }
        if case .failure(let msg) = result {
            BackupLogStore.log("云端同步失败", detail: msg, kind: "sync")
            CloudOps.log(category: "同步", action: "拉取", result: "失败", detail: msg)
        }
        return result
    }

    func pushToCloud() async -> CloudSyncResult {
        let result = await CloudHouseSync.pushAll(houseContext: houseContext)
        if case .success(let added, _, _, let detail) = result {
            BackupLogStore.log("房源上传云端", detail: detail, kind: "sync")
            CloudOps.log(category: "同步", action: "上传", result: "成功", detail: detail)
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

    /// 月度收支汇总（对齐 iOS DataManager.monthlyStats）
    func monthlyStats(month: Int, year: Int) -> (income: Double, expense: Double, net: Double) {
        let calendar = Calendar.current
        var totalIncome: Double = 0
        var totalExpense: Double = 0

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return (0, 0, 0)
        }
        totalIncome += deals.filter { !$0.isDeleted && $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.totalFee }
        totalIncome += miscIncomes.filter { !$0.isDeleted && $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
        totalExpense += miscExpenses.filter { !$0.isDeleted && $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
        return (totalIncome, totalExpense, totalIncome - totalExpense)
    }

    /// 工作台 KPI 统计（对齐 iOS DataManager.dashboardStats）
    func dashboardStats() -> DashboardStats {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        let allProperties = properties.filter { !$0.isDeleted }
        let activeRentalProperties = allProperties.filter { !$0.isTerminated }

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now

        let monthlyDealRecords = deals.filter { !$0.isDeleted && $0.date >= monthStart && $0.date < monthEnd }
        let totalDeals = deals.filter { !$0.isDeleted }.count

        let profits = profitCalculations
        let incomes = miscIncomes.filter { !$0.isDeleted && $0.date >= monthStart && $0.date < monthEnd }
        let expenses = miscExpenses.filter { !$0.isDeleted && $0.date >= monthStart && $0.date < monthEnd }

        let activeProperties = activeRentalProperties.filter { $0.typeDisplayName == "管理" }

        // 本月应收/实收租金
        var monthlyRentReceivable: Double = 0
        var monthlyRentCollected: Double = 0
        for prop in activeRentalProperties {
            for record in prop.monthlyRentRecords {
                if record.year == currentYear && record.month == currentMonth {
                    monthlyRentReceivable += record.amount > 0 ? record.amount : prop.rent
                    if record.isPaid {
                        monthlyRentCollected += record.amount > 0 ? record.amount : prop.rent
                    }
                }
            }
            if !prop.monthlyRentRecords.contains(where: { $0.year == currentYear && $0.month == currentMonth }) {
                monthlyRentReceivable += prop.rent
            }
        }

        var monthlyDealFee: Double = 0
        for deal in monthlyDealRecords { monthlyDealFee += deal.totalFee }

        let totalNetProfit = profits.reduce(0) { $0 + $1.netProfit }

        var monthlyMiscIncome: Double = 0
        for inc in incomes { monthlyMiscIncome += inc.amount }
        var monthlyMiscExpense: Double = 0
        for exp in expenses { monthlyMiscExpense += exp.amount }

        let monthlyNetIncome = monthlyDealFee + monthlyMiscIncome - monthlyMiscExpense

        // 即将到期（30天内）
        var expiringSoon: [Property] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.M.d"
        for prop in activeRentalProperties {
            if let endDate = dateFormatter.date(from: prop.leaseEnd) {
                let days = calendar.dateComponents([.day], from: now, to: endDate).day ?? 0
                if days >= 0 && days <= 30 { expiringSoon.append(prop) }
            }
        }
        expiringSoon.sort { prop1, prop2 in
            let days1 = (calendar.dateComponents([.day], from: now, to: dateFormatter.date(from: prop1.leaseEnd) ?? now).day ?? 0)
            let days2 = (calendar.dateComponents([.day], from: now, to: dateFormatter.date(from: prop2.leaseEnd) ?? now).day ?? 0)
            return days1 < days2
        }

        return DashboardStats(
            totalProperties: activeRentalProperties.count,
            activeProperties: activeProperties.count,
            managedProperties: activeRentalProperties.filter { $0.isManaged }.count,
            monthlyRentReceivable: monthlyRentReceivable,
            monthlyRentCollected: monthlyRentCollected,
            monthlyDealFee: monthlyDealFee,
            totalDeals: totalDeals,
            monthlyDeals: monthlyDealRecords.count,
            packageProfit: totalNetProfit,
            expiringSoon: expiringSoon,
            currentMonth: currentMonth,
            currentYear: currentYear,
            monthlyMiscIncome: monthlyMiscIncome,
            monthlyMiscExpense: monthlyMiscExpense,
            monthlyNetIncome: monthlyNetIncome
        )
    }

    // MARK: - 收租/到期计算

    /// 生成某房源的下一次收租日（按成交日期月周期）
    static func nextRentDate(after dealDate: Date, months: Int = 1) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: dealDate) ?? dealDate
    }
}

// MARK: - 工作台统计结果

struct DashboardStats {
    var totalProperties: Int
    var activeProperties: Int
    var managedProperties: Int
    var monthlyRentReceivable: Double
    var monthlyRentCollected: Double
    var monthlyDealFee: Double
    var totalDeals: Int
    var monthlyDeals: Int
    var packageProfit: Double
    var expiringSoon: [Property]
    var currentMonth: Int
    var currentYear: Int
    var monthlyMiscIncome: Double
    var monthlyMiscExpense: Double
    var monthlyNetIncome: Double
}
