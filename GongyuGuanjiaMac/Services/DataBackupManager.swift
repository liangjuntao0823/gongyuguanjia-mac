import Foundation
import SwiftData

// MARK: - 数据备份管理（快速 = 经营数据 + 房源字段；全量 = 经营数据 + 房源字段 + 媒体文件）
// 备份 zip 结构（Mac 自洽）：
//   app_backup.json   元信息（版本/时间/设备）
//   business.json     经营数据（dict 结构与 iOS exportAllData 一致，可跨端互导）
//   houses.json       房源全字段（含媒体文件名关系）
//   media/            全量备份时的媒体目录

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

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
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
        // 1) 经营数据（iOS 同款 dict 结构）
        var business: [String: Any] = [:]
        business["schemaVersion"] = 3
        business["exportedAt"] = isoFormatter.string(from: Date())
        business["app"] = "公寓管家Mac"
        business["version"] = MacBridge.appVersion

        let deals = (try? mainContext.fetch(FetchDescriptor<DealRecord>())) ?? []
        business["deals"] = deals.map { deal -> [String: Any] in
            [
                "id": deal.id.uuidString,
                "date": isoFormatter.string(from: deal.date),
                "roomNumber": deal.roomNumber,
                "landlord": deal.landlord,
                "unitType": deal.unitType,
                "leaseStart": isoFormatter.string(from: deal.leaseStart),
                "leaseEnd": isoFormatter.string(from: deal.leaseEnd),
                "leaseDuration": deal.leaseDuration,
                "rent": deal.rent,
                "deposit": deal.deposit,
                "prepayment": deal.prepayment,
                "rentDueDay": deal.rentDueDay as Any,
                "agentFeeLandlord": deal.agentFeeLandlord,
                "agentFeeTenant": deal.agentFeeTenant,
                "totalFee": deal.totalFee,
                "manager": deal.manager,
                "source": deal.source,
                "notes": deal.notes,
                "isDeleted": deal.isDeleted,
                "deletedAt": deal.deletedAt.map { isoFormatter.string(from: $0) } as Any
            ]
        }
        let incomes = (try? mainContext.fetch(FetchDescriptor<MiscIncome>())) ?? []
        business["incomes"] = incomes.map { inc -> [String: Any] in
            ["id": inc.id.uuidString, "date": isoFormatter.string(from: inc.date), "item": inc.item, "amount": inc.amount, "notes": inc.notes, "isDeleted": inc.isDeleted, "deletedAt": inc.deletedAt.map { isoFormatter.string(from: $0) } as Any]
        }
        let expenses = (try? mainContext.fetch(FetchDescriptor<MiscExpense>())) ?? []
        business["expenses"] = expenses.map { exp -> [String: Any] in
            ["id": exp.id.uuidString, "date": isoFormatter.string(from: exp.date), "item": exp.item, "amount": exp.amount, "notes": exp.notes, "isDeleted": exp.isDeleted, "deletedAt": exp.deletedAt.map { isoFormatter.string(from: $0) } as Any]
        }
        let properties = (try? mainContext.fetch(FetchDescriptor<Property>())) ?? []
        business["properties"] = properties.map { prop -> [String: Any] in
            [
                "id": prop.id.uuidString,
                "roomNumber": prop.roomNumber,
                "landlord": prop.landlord,
                "unitType": prop.unitType,
                "rent": prop.rent,
                "deposit": prop.deposit,
                "prepayment": prop.prepayment,
                "leaseStart": prop.leaseStart,
                "leaseEnd": prop.leaseEnd,
                "leaseDuration": prop.leaseDuration,
                "rentDueDay": prop.rentDueDay,
                "waterMeterBase": prop.waterMeterBase,
                "electricMeterBase": prop.electricMeterBase,
                "propertyType": prop.propertyType,
                "notes": prop.notes,
                "isTerminated": prop.isTerminated,
                "terminationDate": prop.terminationDate.map { isoFormatter.string(from: $0) } as Any,
                "terminationReason": prop.terminationReason,
                "depositRefundStatus": prop.depositRefundStatus,
                "roomDamageStatus": prop.roomDamageStatus,
                "utilitySettlementStatus": prop.utilitySettlementStatus,
                "terminationPerson": prop.terminationPerson,
                "terminationPhone": prop.terminationPhone,
                "isDeleted": prop.isDeleted,
                "deletedAt": prop.deletedAt.map { isoFormatter.string(from: $0) } as Any,
                "createdAt": isoFormatter.string(from: prop.createdAt),
                "monthlyRentRecords": prop.monthlyRentRecords.map { ["id": $0.id.uuidString, "year": $0.year, "month": $0.month, "amount": $0.amount, "isPaid": $0.isPaid, "paidDate": $0.paidDate.map { isoFormatter.string(from: $0) } as Any] },
                "quarterlyUtilityRecords": prop.quarterlyUtilityRecords.map { ["id": $0.id.uuidString, "quarter": $0.quarter, "electricAmount": $0.electricAmount, "waterAmount": $0.waterAmount, "isSettled": $0.isSettled] },
                "utilitySettlementFrequency": prop.utilitySettlementFrequency,
                "utilitySettlementRecords": prop.utilitySettlementRecords.map { ["id": $0.id.uuidString, "year": $0.year, "period": $0.period, "frequency": $0.frequency, "electricAmount": $0.electricAmount, "waterAmount": $0.waterAmount, "balance": $0.balance, "isSettled": $0.isSettled, "statement": $0.statement, "settledAt": $0.settledAt.map { isoFormatter.string(from: $0) } as Any, "dueDate": $0.dueDate.map { isoFormatter.string(from: $0) } as Any] }
            ]
        }
        let payouts = (try? mainContext.fetch(FetchDescriptor<PayoutRecord>())) ?? []
        business["payouts"] = payouts.map { p -> [String: Any] in
            [
                "id": p.id.uuidString,
                "roomNumber": p.roomNumber,
                "manager": p.manager,
                "unitType": p.unitType,
                "monthlyRent": p.monthlyRent as Any,
                "annualRent": p.annualRent,
                "deposit": p.deposit,
                "leaseStartDate": isoFormatter.string(from: p.leaseStartDate),
                "leaseEndDate": isoFormatter.string(from: p.leaseEndDate),
                "leaseDuration": p.leaseDuration,
                "rentFreeDays": p.rentFreeDays,
                "waterMeterBase": p.waterMeterBase,
                "electricMeterBase": p.electricMeterBase,
                "rentDueDay": p.rentDueDay,
                "paymentMethod": p.paymentMethod,
                "notes": p.notes,
                "isDeleted": p.isDeleted,
                "deletedAt": p.deletedAt.map { isoFormatter.string(from: $0) } as Any,
                "monthlyPayouts": p.monthlyPayouts.map { ["id": $0.id.uuidString, "month": $0.month, "amount": $0.amount, "isPaid": $0.isPaid, "paidDate": $0.paidDate.map { isoFormatter.string(from: $0) } as Any] },
                "monthlyUtilityRecords": p.monthlyUtilityRecords.map { ["id": $0.id.uuidString, "date": isoFormatter.string(from: $0.date), "waterAmount": $0.waterAmount, "electricAmount": $0.electricAmount, "isSettled": $0.isSettled] }
            ]
        }
        let todos = (try? mainContext.fetch(FetchDescriptor<TodoItem>())) ?? []
        business["todos"] = todos.map { item -> [String: Any] in
            [
                "id": item.id.uuidString,
                "content": item.content,
                "createdDate": isoFormatter.string(from: item.createdDate),
                "isCompleted": item.isCompleted,
                "completedDate": item.completedDate.map { isoFormatter.string(from: $0) } as Any,
                "sortOrder": item.sortOrder,
                "reminderDate": item.reminderDate.map { isoFormatter.string(from: $0) } as Any,
                "isDeleted": item.isDeleted,
                "deletedAt": item.deletedAt.map { isoFormatter.string(from: $0) } as Any
            ]
        }
        let utilityHistories = (try? mainContext.fetch(FetchDescriptor<UtilitySettlementHistory>())) ?? []
        business["utilityHistories"] = utilityHistories.map { h -> [String: Any] in
            ["id": h.id.uuidString, "roomNumber": h.roomNumber, "statement": h.statement, "settledAt": isoFormatter.string(from: h.settledAt), "includesMaster": h.includesMaster, "electricLatest": h.electricLatest, "waterLatest": h.waterLatest, "electricCost": h.electricCost, "waterCost": h.waterCost, "balance": h.balance, "sortOrder": h.sortOrder]
        }

        guard let businessData = try? JSONSerialization.data(withJSONObject: business, options: .prettyPrinted) else {
            return .failure("序列化经营数据失败")
        }

        // 2) 房源数据
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
        guard let houseData = try? encoder.encode(houseBundle) else { return .failure("序列化房源数据失败") }
        let meta = AppBackupMeta(app: "公寓管家Mac", version: MacBridge.appVersion,
                                 createdAt: Date(), device: MacBridge.deviceName)
        guard let metaData = try? encoder.encode(meta) else { return .failure("序列化元信息失败") }

        // 3) 写临时目录
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

        // 4) 打包
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
        let decoder = JSONDecoder()

        switch ZipStore.unzip(zipURL, to: tmpDir) {
        case .success: break
        case .failure(let e): return .failure(e)
        }

        // 1) 经营数据（dict 解析，兼容 iOS exportAllData 格式）
        let businessURL = tmpDir.appendingPathComponent("business.json")
        guard FileManager.default.fileExists(atPath: businessURL.path),
              let data = try? Data(contentsOf: businessURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(AppError.message("备份缺少经营数据（business.json）"))
        }

        // 清空现有经营数据
        for deal in (try? mainContext.fetch(FetchDescriptor<DealRecord>())) ?? [] { mainContext.delete(deal) }
        for prop in (try? mainContext.fetch(FetchDescriptor<Property>())) ?? [] { mainContext.delete(prop) }
        for pay in (try? mainContext.fetch(FetchDescriptor<PayoutRecord>())) ?? [] { mainContext.delete(pay) }
        for inc in (try? mainContext.fetch(FetchDescriptor<MiscIncome>())) ?? [] { mainContext.delete(inc) }
        for exp in (try? mainContext.fetch(FetchDescriptor<MiscExpense>())) ?? [] { mainContext.delete(exp) }
        for todo in (try? mainContext.fetch(FetchDescriptor<TodoItem>())) ?? [] { mainContext.delete(todo) }
        for h in (try? mainContext.fetch(FetchDescriptor<UtilitySettlementHistory>())) ?? [] { mainContext.delete(h) }
        try? mainContext.save()

        let dbl: (Any?) -> Double = { v in (v as? Double) ?? Double(v as? Int ?? 0) }
        let intVal: (Any?) -> Int = { v in (v as? Int) ?? Int(v as? Double ?? 0) }
        let strVal: (Any?) -> String = { v in v as? String ?? "" }
        let dateVal: (Any?) -> Date? = { v in
            guard let s = v as? String else { return nil }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
        }

        for d in (dict["deals"] as? [[String: Any]]) ?? [] {
            let rec = DealRecord(id: UUID(uuidString: strVal(d["id"])) ?? UUID(),
                                 date: dateVal(d["date"]) ?? Date(),
                                 roomNumber: strVal(d["roomNumber"]), landlord: strVal(d["landlord"]),
                                 unitType: strVal(d["unitType"]),
                                 leaseStart: dateVal(d["leaseStart"]) ?? Date(),
                                 leaseEnd: dateVal(d["leaseEnd"]) ?? Date(),
                                 leaseDuration: strVal(d["leaseDuration"]), rent: dbl(d["rent"]),
                                 deposit: dbl(d["deposit"]), prepayment: dbl(d["prepayment"]),
                                 rentDueDay: (d["rentDueDay"] is NSNull || d["rentDueDay"] == nil) ? nil : intVal(d["rentDueDay"]),
                                 agentFeeLandlord: dbl(d["agentFeeLandlord"]),
                                 agentFeeTenant: dbl(d["agentFeeTenant"]), totalFee: dbl(d["totalFee"]),
                                 manager: strVal(d["manager"]), source: strVal(d["source"]), notes: strVal(d["notes"]))
            rec.isDeleted = d["isDeleted"] as? Bool ?? false
            rec.deletedAt = dateVal(d["deletedAt"])
            mainContext.insert(rec)
        }
        for inc in (dict["incomes"] as? [[String: Any]]) ?? [] {
            let rec = MiscIncome(id: UUID(uuidString: strVal(inc["id"])) ?? UUID(), date: dateVal(inc["date"]) ?? Date(), item: strVal(inc["item"]), amount: dbl(inc["amount"]), notes: strVal(inc["notes"]))
            rec.isDeleted = inc["isDeleted"] as? Bool ?? false
            rec.deletedAt = dateVal(inc["deletedAt"])
            mainContext.insert(rec)
        }
        for exp in (dict["expenses"] as? [[String: Any]]) ?? [] {
            let rec = MiscExpense(id: UUID(uuidString: strVal(exp["id"])) ?? UUID(), date: dateVal(exp["date"]) ?? Date(), item: strVal(exp["item"]), amount: dbl(exp["amount"]), notes: strVal(exp["notes"]))
            rec.isDeleted = exp["isDeleted"] as? Bool ?? false
            rec.deletedAt = dateVal(exp["deletedAt"])
            mainContext.insert(rec)
        }
        for p in (dict["properties"] as? [[String: Any]]) ?? [] {
            let prop = Property(id: UUID(uuidString: strVal(p["id"])) ?? UUID(),
                                roomNumber: strVal(p["roomNumber"]), landlord: strVal(p["landlord"]),
                                unitType: strVal(p["unitType"]),
                                rent: dbl(p["rent"]), deposit: dbl(p["deposit"]), prepayment: dbl(p["prepayment"]),
                                leaseStart: strVal(p["leaseStart"]), leaseEnd: strVal(p["leaseEnd"]),
                                leaseDuration: strVal(p["leaseDuration"]),
                                rentDueDay: intVal(p["rentDueDay"]), waterMeterBase: intVal(p["waterMeterBase"]),
                                electricMeterBase: intVal(p["electricMeterBase"]),
                                propertyType: strVal(p["propertyType"]), notes: strVal(p["notes"]),
                                isTerminated: p["isTerminated"] as? Bool ?? false,
                                terminationDate: dateVal(p["terminationDate"]),
                                terminationReason: strVal(p["terminationReason"]),
                                depositRefundStatus: strVal(p["depositRefundStatus"]),
                                roomDamageStatus: strVal(p["roomDamageStatus"]),
                                utilitySettlementStatus: strVal(p["utilitySettlementStatus"]),
                                terminationPerson: strVal(p["terminationPerson"]),
                                terminationPhone: strVal(p["terminationPhone"]))
            if let createdAt = dateVal(p["createdAt"]) { prop.createdAt = createdAt }
            prop.utilitySettlementFrequency = strVal(p["utilitySettlementFrequency"]).isEmpty ? "quarterly" : strVal(p["utilitySettlementFrequency"])
            prop.isDeleted = p["isDeleted"] as? Bool ?? false
            prop.deletedAt = dateVal(p["deletedAt"])
            mainContext.insert(prop)
            for r in (p["utilitySettlementRecords"] as? [[String: Any]]) ?? [] {
                let rec = UtilitySettlementRecord(id: UUID(uuidString: strVal(r["id"])) ?? UUID(), year: intVal(r["year"]), period: intVal(r["period"]),
                                                  frequency: strVal(r["frequency"]).isEmpty ? prop.utilitySettlementFrequency : strVal(r["frequency"]),
                                                  electricAmount: dbl(r["electricAmount"]), waterAmount: dbl(r["waterAmount"]),
                                                  balance: dbl(r["balance"]), isSettled: r["isSettled"] as? Bool ?? false,
                                                  statement: strVal(r["statement"]), settledAt: dateVal(r["settledAt"]), dueDate: dateVal(r["dueDate"]))
                mainContext.insert(rec)
                prop.utilitySettlementRecords.append(rec)
            }
            for m in (p["monthlyRentRecords"] as? [[String: Any]]) ?? [] {
                let rec = RentMonthRecord(id: UUID(uuidString: strVal(m["id"])) ?? UUID(), year: intVal(m["year"]), month: intVal(m["month"]), amount: dbl(m["amount"]), isPaid: m["isPaid"] as? Bool ?? false)
                rec.paidDate = dateVal(m["paidDate"])
                mainContext.insert(rec)
                prop.monthlyRentRecords.append(rec)
            }
            for q in (p["quarterlyUtilityRecords"] as? [[String: Any]]) ?? [] {
                let rec = UtilityQuarterRecord(id: UUID(uuidString: strVal(q["id"])) ?? UUID(), quarter: intVal(q["quarter"]), electricAmount: dbl(q["electricAmount"]), waterAmount: dbl(q["waterAmount"]), isSettled: q["isSettled"] as? Bool ?? false)
                mainContext.insert(rec)
                prop.quarterlyUtilityRecords.append(rec)
            }
        }
        for h in (dict["utilityHistories"] as? [[String: Any]]) ?? [] {
            mainContext.insert(UtilitySettlementHistory(id: UUID(uuidString: strVal(h["id"])) ?? UUID(), roomNumber: strVal(h["roomNumber"]), statement: strVal(h["statement"]),
                                                        settledAt: dateVal(h["settledAt"]) ?? Date(),
                                                        includesMaster: h["includesMaster"] as? Bool ?? false,
                                                        electricLatest: dbl(h["electricLatest"]), waterLatest: dbl(h["waterLatest"]),
                                                        electricCost: dbl(h["electricCost"]), waterCost: dbl(h["waterCost"]),
                                                        balance: dbl(h["balance"]), sortOrder: intVal(h["sortOrder"])))
        }
        for item in (dict["todos"] as? [[String: Any]]) ?? [] {
            let todo = TodoItem(id: UUID(uuidString: strVal(item["id"])) ?? UUID(), content: strVal(item["content"]),
                                createdDate: dateVal(item["createdDate"]) ?? Date(),
                                isCompleted: item["isCompleted"] as? Bool ?? false,
                                completedDate: dateVal(item["completedDate"]),
                                sortOrder: intVal(item["sortOrder"]),
                                reminderDate: dateVal(item["reminderDate"]),
                                isDeleted: item["isDeleted"] as? Bool ?? false,
                                deletedAt: dateVal(item["deletedAt"]))
            mainContext.insert(todo)
        }
        for p in (dict["payouts"] as? [[String: Any]]) ?? [] {
            let payout = PayoutRecord(id: UUID(uuidString: strVal(p["id"])) ?? UUID(),
                                      roomNumber: strVal(p["roomNumber"]), manager: strVal(p["manager"]),
                                      unitType: strVal(p["unitType"]),
                                      leaseStartDate: dateVal(p["leaseStartDate"]) ?? Date(),
                                      leaseEndDate: dateVal(p["leaseEndDate"]) ?? Date(),
                                      leaseDuration: strVal(p["leaseDuration"]), rentFreeDays: intVal(p["rentFreeDays"]),
                                      monthlyRent: (p["monthlyRent"] is NSNull || p["monthlyRent"] == nil) ? nil : dbl(p["monthlyRent"]),
                                      annualRent: dbl(p["annualRent"]), deposit: dbl(p["deposit"]),
                                      waterMeterBase: intVal(p["waterMeterBase"]), electricMeterBase: intVal(p["electricMeterBase"]),
                                      rentDueDay: intVal(p["rentDueDay"]), paymentMethod: strVal(p["paymentMethod"]), notes: strVal(p["notes"]))
            payout.isDeleted = p["isDeleted"] as? Bool ?? false
            payout.deletedAt = dateVal(p["deletedAt"])
            mainContext.insert(payout)
            for m in (p["monthlyPayouts"] as? [[String: Any]]) ?? [] {
                let rec = PayoutMonthRecord(id: UUID(uuidString: strVal(m["id"])) ?? UUID(), month: intVal(m["month"]), amount: dbl(m["amount"]), isPaid: m["isPaid"] as? Bool ?? false)
                rec.paidDate = dateVal(m["paidDate"])
                mainContext.insert(rec)
                payout.monthlyPayouts.append(rec)
            }
            for u in (p["monthlyUtilityRecords"] as? [[String: Any]]) ?? [] {
                let rec = PayoutUtilityRecord(id: UUID(uuidString: strVal(u["id"])) ?? UUID(), date: dateVal(u["date"]) ?? Date(), waterAmount: dbl(u["waterAmount"]), electricAmount: dbl(u["electricAmount"]), isSettled: u["isSettled"] as? Bool ?? false)
                mainContext.insert(rec)
                payout.monthlyUtilityRecords.append(rec)
            }
        }
        try? mainContext.save()

        // 2) 房源数据（可选）
        var hasHouses = false
        let housesURL = tmpDir.appendingPathComponent("houses.json")
        if let houseContext = houseContext, FileManager.default.fileExists(atPath: housesURL.path),
           let data = try? Data(contentsOf: housesURL),
           let bundle = try? decoder.decode(HouseBundleDTO.self, from: data) {
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
