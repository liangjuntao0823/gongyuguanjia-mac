import Foundation
import SwiftData

// MARK: - 数据备份管理（快速 = 经营数据 + 房源字段；全量 = 经营数据 + 房源字段 + 媒体文件）
// 备份 zip 结构（Mac 自洽，与 iOS 版同思路）：
//   app_backup.json   元信息（版本/时间/设备）
//   business.json     经营数据（成交/物业/支出）
//   houses.json       房源全字段（含媒体文件名关系）
//   media/            全量备份时的媒体目录

struct BusinessBackupDTO: Codable {
    var deals: [DealDTO]
    var properties: [PropertyDTO]
    var payouts: [PayoutDTO]
}

struct DealDTO: Codable {
    var id: UUID
    var roomNo: String
    var dealDate: Date
    var dealType: String
    var price: Double
    var commission: Double
    var fee: Double
    var paidBy: String
    var remark: String
    var createdAt: Date
    var updatedAt: Date
}

struct PropertyDTO: Codable {
    var id: UUID
    var name: String
    var address: String
    var monthlyRent: Double
    var monthlyExpense: Double
    var remark: String
    var createdAt: Date
    var updatedAt: Date
}

struct PayoutDTO: Codable {
    var id: UUID
    var amount: Double
    var category: String
    var date: Date
    var remark: String
    var createdAt: Date
    var updatedAt: Date
}

struct AppBackupMeta: Codable {
    var app: String
    var version: String
    var createdAt: Date
    var device: String
}

enum BackupResult {
    case success(URL)
    case failure(String)
}

enum DataBackupManager {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: 创建备份

    /// 快速备份：经营数据 + 房源字段（不含媒体文件）
    static func createQuickBackup(mainContext: ModelContext, to zipURL: URL) async -> BackupResult {
        await createBackup(mainContext: mainContext, houseContext: nil, to: zipURL, includeMedia: false)
    }

    /// 全量备份：经营数据 + 房源字段 + 媒体
    static func createFullBackup(mainContext: ModelContext, houseContext: ModelContext, to zipURL: URL) async -> BackupResult {
        await createBackup(mainContext: mainContext, houseContext: houseContext, to: zipURL, includeMedia: true)
    }

    private static func createBackup(mainContext: ModelContext, houseContext: ModelContext?, to zipURL: URL, includeMedia: Bool) async -> BackupResult {
        // 1) 序列化数据
        let deals = (try? mainContext.fetch(FetchDescriptor<DealRecord>())) ?? []
        let properties = (try? mainContext.fetch(FetchDescriptor<Property>())) ?? []
        let payouts = (try? mainContext.fetch(FetchDescriptor<PayoutRecord>())) ?? []
        let business = BusinessBackupDTO(
            deals: deals.map {
                DealDTO(id: $0.id, roomNo: $0.roomNo, dealDate: $0.dealDate, dealType: $0.dealType,
                        price: $0.price, commission: $0.commission, fee: $0.fee, paidBy: $0.paidBy,
                        remark: $0.remark, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            properties: properties.map {
                PropertyDTO(id: $0.id, name: $0.name, address: $0.address,
                            monthlyRent: $0.monthlyRent, monthlyExpense: $0.monthlyExpense,
                            remark: $0.remark, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            payouts: payouts.map {
                PayoutDTO(id: $0.id, amount: $0.amount, category: $0.category, date: $0.date,
                          remark: $0.remark, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            }
        )
        var houseBundle: HouseBundleDTO?
        if let houseContext = houseContext {
            let houses = (try? houseContext.fetch(FetchDescriptor<House>())) ?? []
            houseBundle = HouseBundleDTO(
                schemaVersion: 1,
                houses: houses.map { h in
                    HouseExportDTO(
                        id: h.id, roomNo: h.roomNo, tower: h.tower, landlord: h.landlord,
                        layout: h.layout, price: h.price, password: h.password, remark: h.remark,
                        statusRaw: h.statusRaw, createdAt: h.createdAt, updatedAt: h.updatedAt,
                        isDeleted: h.isDeleted, deletedAt: h.deletedAt,
                        mediaItems: h.mediaItems.map { MediaExportDTO(fileName: $0.fileName, kind: $0.kind) }
                    )
                }
            )
        }

        guard let businessData = try? encoder.encode(business) else { return .failure("序列化经营数据失败") }
        guard let houseData = try? encoder.encode(houseBundle) else { return .failure("序列化房源数据失败") }
        let meta = AppBackupMeta(app: "公寓管家Mac", version: MacBridge.appVersion,
                                 createdAt: Date(), device: MacBridge.deviceName)
        guard let metaData = try? encoder.encode(meta) else { return .failure("序列化元信息失败") }

        // 2) 写临时目录
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        do {
            try businessData.write(to: tmpDir.appendingPathComponent("business.json"))
            try houseData.write(to: tmpDir.appendingPathComponent("houses.json"))
            try metaData.write(to: tmpDir.appendingPathComponent("app_backup.json"))
            if includeMedia {
                let mediaDir = tmpDir.appendingPathComponent("media", isDirectory: true)
                try? FileManager.default.removeItem(at: mediaDir)
                try? FileManager.default.copyItem(at: DataRoot.mediaDirectory, to: mediaDir)
            }
        } catch {
            return .failure("写入备份内容失败：\(error.localizedDescription)")
        }

        // 3) 打包
        let result = ZipStore.zipDirectory(tmpDir, to: zipURL)
        try? FileManager.default.removeItem(at: tmpDir)
        switch result {
        case .success:
            return .success(zipURL)
        case .failure(let e):
            return .failure(e.localizedDescription)
        }
    }

    // MARK: 恢复备份

    /// 从 zip 恢复（清空现有数据后导入）。returns 是否包含房源数据
    static func restore(from zipURL: URL, mainContext: ModelContext, houseContext: ModelContext?) async -> Result<Bool, Error> {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        switch ZipStore.unzip(zipURL, to: tmpDir) {
        case .success: break
        case .failure(let e): return .failure(e)
        }

        // 1) 经营数据
        let businessURL = tmpDir.appendingPathComponent("business.json")
        guard FileManager.default.fileExists(atPath: businessURL.path),
              let data = try? Data(contentsOf: businessURL),
              let business = try? decoder.decode(BusinessBackupDTO.self, from: data) else {
            return .failure(AppError.message("备份缺少经营数据（business.json）"))
        }

        // 清空现有经营数据
        for deal in (try? mainContext.fetch(FetchDescriptor<DealRecord>())) ?? [] { mainContext.delete(deal) }
        for prop in (try? mainContext.fetch(FetchDescriptor<Property>())) ?? [] { mainContext.delete(prop) }
        for pay in (try? mainContext.fetch(FetchDescriptor<PayoutRecord>())) ?? [] { mainContext.delete(pay) }
        try? mainContext.save()

        for d in business.deals {
            let deal = DealRecord(roomNo: d.roomNo, dealDate: d.dealDate, dealType: d.dealType,
                                  price: d.price, commission: d.commission, fee: d.fee,
                                  paidBy: d.paidBy, remark: d.remark)
            deal.id = d.id
            deal.createdAt = d.createdAt
            deal.updatedAt = d.updatedAt
            mainContext.insert(deal)
        }
        for p in business.properties {
            let prop = Property(name: p.name, address: p.address, monthlyRent: p.monthlyRent,
                                monthlyExpense: p.monthlyExpense, remark: p.remark)
            prop.id = p.id
            prop.createdAt = p.createdAt
            prop.updatedAt = p.updatedAt
            mainContext.insert(prop)
        }
        for p in business.payouts {
            let pay = PayoutRecord(amount: p.amount, category: p.category, date: p.date, remark: p.remark)
            pay.id = p.id
            pay.createdAt = p.createdAt
            pay.updatedAt = p.updatedAt
            mainContext.insert(pay)
        }
        try? mainContext.save()

        // 2) 房源数据（可选）
        var hasHouses = false
        let housesURL = tmpDir.appendingPathComponent("houses.json")
        if let houseContext = houseContext, FileManager.default.fileExists(atPath: housesURL.path),
           let data = try? Data(contentsOf: housesURL),
           let bundle = try? decoder.decode(HouseBundleDTO.self, from: data) {
            // 清空现有房源
            for h in (try? houseContext.fetch(FetchDescriptor<House>())) ?? [] { houseContext.delete(h) }
            try? houseContext.save()
            for exp in bundle.houses {
                let house = House(roomNo: exp.roomNo, tower: exp.tower, landlord: exp.landlord,
                                  layout: exp.layout, price: exp.price, password: exp.password,
                                  remark: exp.remark, status: exp.statusRaw)
                house.id = exp.id
                house.createdAt = exp.createdAt
                house.updatedAt = exp.updatedAt
                house.isDeleted = exp.isDeleted
                house.deletedAt = exp.deletedAt
                house.cloudStatus = .local
                for m in exp.mediaItems {
                    house.mediaItems.append(MediaItem(fileName: m.fileName, kind: m.kind))
                }
                houseContext.insert(house)
            }
            try? houseContext.save()
            hasHouses = true
        }

        // 3) 媒体（全量备份恢复）
        let mediaDir = tmpDir.appendingPathComponent("media")
        if FileManager.default.fileExists(atPath: mediaDir.path) {
            // 合并进本地媒体目录（先删旧再拷新）
            try? FileManager.default.removeItem(at: DataRoot.mediaDirectory)
            try? FileManager.default.createDirectory(at: DataRoot.mediaDirectory, withIntermediateDirectories: true)
            if let items = try? FileManager.default.contentsOfDirectory(atPath: mediaDir.path) {
                for item in items {
                    let src = mediaDir.appendingPathComponent(item)
                    let dst = DataRoot.mediaDirectory.appendingPathComponent(item)
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }

        return .success(hasHouses)
    }
}
