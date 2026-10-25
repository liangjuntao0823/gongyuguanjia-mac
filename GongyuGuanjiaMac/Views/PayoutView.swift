import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 包租板块（对齐 iOS：包租合同卡片 + 打租周期 + 详情 + 导入导出）

struct PayoutView: View {
    @ObservedObject var manager: DataManager
    private static let xlsType = UTType(filenameExtension: "xls") ?? .data
    private static let csvType = UTType(filenameExtension: "csv") ?? .data

    @State private var showingAddPayout = false
    @State private var editingPayout: PayoutRecord?
    @State private var selectedPayout: PayoutRecord?
    @State private var payoutToDelete: PayoutRecord?
    @State private var searchText = ""

    private var payouts: [PayoutRecord] { manager.payouts.filter { $0.isDeleted != true } }

    private var filteredPayouts: [PayoutRecord] {
        let list = searchText.isEmpty ? payouts : payouts.filter {
            $0.roomNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.manager.localizedCaseInsensitiveContains(searchText) ||
            $0.unitType.localizedCaseInsensitiveContains(searchText)
        }
        return list.sorted { a, b in
            let aInfo = nextPayoutInfo(for: a)
            let bInfo = nextPayoutInfo(for: b)
            if aInfo.isOverdue != bInfo.isOverdue { return aInfo.isOverdue && !bInfo.isOverdue }
            if aInfo.month != bInfo.month { return aInfo.month < bInfo.month }
            return a.roomNumber < b.roomNumber
        }
    }

    // MARK: 周期计算（对齐 iOS）
    private func periodCount(for payout: PayoutRecord) -> Int {
        switch payout.paymentMethod {
        case "季付": return 4
        case "半年付": return 2
        case "年付": return 1
        default: return 12
        }
    }
    private func periodMonths(for payout: PayoutRecord) -> Int { 12 / periodCount(for: payout) }
    private func periodMonth(for payout: PayoutRecord, index: Int) -> Int {
        switch payout.paymentMethod {
        case "季付": return (index + 1) * 3
        case "半年付": return (index + 1) * 6
        case "年付": return 12
        default: return (index + 1) * 1
        }
    }
    private func nextPayoutInfo(for payout: PayoutRecord) -> (month: Int, day: Int, amount: Double, isOverdue: Bool, daysDiff: Int) {
        let calendar = Calendar.current
        let now = Date()
        let periodCount = self.periodCount(for: payout)
        let periodMonths = 12 / periodCount
        let startMonth = calendar.component(.month, from: payout.leaseStartDate)
        let startYear = calendar.component(.year, from: payout.leaseStartDate)
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        for i in 0..<periodCount {
            // 查找记录用固定期数月（与详情页 periodMonth 一致）
            let recordMonth = periodMonth(for: payout, index: i)
            var displayMonth = startMonth + i * periodMonths
            var displayYear = startYear
            while displayMonth > 12 { displayMonth -= 12; displayYear += 1 }
            let defaultAmount = (payout.monthlyRent ?? 0) * Double(periodMonths)
            let record = payout.monthlyPayouts.first { $0.month == recordMonth }
            let amount = record?.amount ?? defaultAmount
            var dateComps = DateComponents()
            dateComps.year = displayYear
            dateComps.month = displayMonth
            dateComps.day = payout.rentDueDay
            if let dueDate = calendar.date(from: dateComps) {
                let daysDiff = calendar.dateComponents([.day], from: now, to: dueDate).day ?? 0
                let isPaid = record?.isPaid ?? false
                if daysDiff >= -15 && !isPaid {
                    let overdue = daysDiff < 0
                    return (recordMonth, payout.rentDueDay, amount, overdue, daysDiff)
                }
            }
            _ = currentYear; _ = currentMonth
        }
        return (0, payout.rentDueDay, (payout.monthlyRent ?? 0) * Double(periodMonths), false, 999)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("包租管理").font(.system(size: 19, weight: .bold))
                Text("共 \(payouts.count) 份合同")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText3)
                Spacer()
                TextField("搜索房号/包租人/户型…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Button { exportToExcel() } label: { Label("导出 Excel", systemImage: "square.and.arrow.up") }
                    .macSecondaryButton()
                Button { importFromFile() } label: { Label("导入", systemImage: "square.and.arrow.down") }
                    .macSecondaryButton()
                Button { showingAddPayout = true } label: { Label("新增包租合同", systemImage: "plus") }
                    .macPrimaryButton()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Divider()

            if filteredPayouts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "briefcase").font(.system(size: 40)).foregroundColor(.gray)
                    Text("暂无包租合同").font(.system(size: 14)).foregroundColor(.themeText3)
                    Button("新增包租合同") { showingAddPayout = true }.macSecondaryButton()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredPayouts) { payout in
                            PayoutRow(payout: payout,
                                      nextInfo: nextPayoutInfo(for: payout),
                                      onTap: { selectedPayout = payout },
                                      onEdit: { editingPayout = payout },
                                      onDelete: { payoutToDelete = payout })
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showingAddPayout) { PayoutEditor(manager: manager, payout: nil) { showingAddPayout = false } }
        .sheet(item: $editingPayout) { payout in PayoutEditor(manager: manager, payout: payout) { editingPayout = nil } }
        .sheet(item: $selectedPayout) { payout in PayoutDetailView(manager: manager, payout: payout) { selectedPayout = nil } }
        .confirmationDialog("确定删除包租合同 \(payoutToDelete?.roomNumber ?? "") 吗？删除后可在回收站还原。",
                            isPresented: Binding(get: { payoutToDelete != nil }, set: { if !$0 { payoutToDelete = nil } })) {
            Button("确定删除", role: .destructive) {
                if let payout = payoutToDelete { manager.softDeletePayout(payout); MacToastCenter.show("已删除") }
                payoutToDelete = nil
            }
            Button("取消", role: .cancel) { payoutToDelete = nil }
        }
    }

    private func exportToExcel() {
        var rows: [[String]] = [["房号", "包租人", "户型", "起租日", "到期日", "年租金", "免租期", "支付方式", "备注"]]
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        for p in filteredPayouts {
            rows.append([p.roomNumber, p.manager, p.unitType,
                         df.string(from: p.leaseStartDate), df.string(from: p.leaseEndDate),
                         "\(Int(p.annualRent))", "\(p.rentFreeDays)天", p.paymentMethod, p.notes])
        }
        let data = ExcelService.makeExcelHTML(rows: rows, sheetName: "包租管理")
        MacBridge.saveFile(defaultName: "包租管理_\(BackupTimestamp.string()).xls", allowedTypes: [Self.xlsType, .spreadsheet]) { url in
            guard let url = url else { return }
            try? data.write(to: url)
            MacToastCenter.show("已导出 \(rows.count - 1) 份合同")
        }
    }

    private func importFromFile() {
        MacBridge.openFiles(allowedTypes: [Self.xlsType, Self.csvType, .spreadsheet], allowsMultiple: false) { urls in
            guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
            let rows = ExcelService.parseImported(data)
            guard rows.count > 1 else { MacToastCenter.show("导入文件为空或格式不支持"); return }
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
            var added = 0
            for row in rows.dropFirst() where row.count >= 3 {
                _ = manager.addPayout(roomNumber: row[0], manager: row.count > 1 ? row[1] : "",
                                      unitType: row.count > 2 ? row[2] : "",
                                      leaseStartDate: df.date(from: row.count > 3 ? row[3] : "") ?? Date(),
                                      leaseEndDate: df.date(from: row.count > 4 ? row[4] : "") ?? Date(),
                                      leaseDuration: "", rentFreeDays: Int(row.count > 6 ? row[6] : "0") ?? 0,
                                      monthlyRent: nil,
                                      annualRent: Double(row.count > 5 ? row[5].replacingOccurrences(of: ",", with: "") : "") ?? 0,
                                      rentDueDay: 1, paymentMethod: row.count > 7 ? row[7] : "月付",
                                      notes: row.count > 8 ? row[8] : "")
                added += 1
            }
            MacToastCenter.show("已导入 \(added) 份合同")
        }
    }
}

// MARK: - 包租卡片

struct PayoutRow: View {
    let payout: PayoutRecord
    let nextInfo: (month: Int, day: Int, amount: Double, isOverdue: Bool, daysDiff: Int)
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var periodCount: Int {
        switch payout.paymentMethod {
        case "季付": return 4
        case "半年付": return 2
        case "年付": return 1
        default: return 12
        }
    }
    private func periodMonth(for index: Int) -> Int {
        switch payout.paymentMethod {
        case "季付": return (index + 1) * 3
        case "半年付": return (index + 1) * 6
        case "年付": return 12
        default: return (index + 1) * 1
        }
    }
    private var validMonths: Set<Int> { Set((0..<periodCount).map { periodMonth(for: $0) }) }
    private var paidCount: Int { payout.monthlyPayouts.filter { $0.isPaid && validMonths.contains($0.month) }.count }
    private var paidAmount: Double { payout.monthlyPayouts.filter { $0.isPaid && validMonths.contains($0.month) }.reduce(0) { $0 + $1.amount } }
    private var paidUtility: Double { payout.monthlyUtilityRecords.filter(\.isSettled).reduce(0) { $0 + $1.waterAmount + $1.electricAmount } }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("\(payout.rentDueDay)号")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(nextInfo.isOverdue ? Color.red.opacity(0.85) : Color(hex: "7B61FF").opacity(0.85))
                        .clipShape(Circle())
                    Text(payout.roomNumber)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.themeText)
                }
                .frame(width: 70)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(payout.manager).font(.system(size: 13, weight: .semibold)).foregroundColor(.themeText)
                        Text(payout.unitType).font(.system(size: 12)).foregroundColor(.themeText2)
                        Text(payout.paymentMethod).font(.system(size: 11)).foregroundColor(.themeAccentDark)
                    }
                    HStack(spacing: 8) {
                        Text("年租 ¥\(Int(payout.annualRent))").font(.system(size: 12, weight: .semibold)).foregroundColor(.themeText)
                        if payout.monthlyRent != nil { Text("月打租 ¥\(Int(payout.monthlyRent ?? 0))").font(.system(size: 11)).foregroundColor(.themeText3) }
                        Text("免租 \(payout.rentFreeDays)天").font(.system(size: 11)).foregroundColor(.themeText3)
                    }
                    if nextInfo.month > 0 {
                        Text("下一期：\(nextInfo.month)月\(nextInfo.day)日 应付 ¥\(Int(nextInfo.amount)) \(nextInfo.isOverdue ? "（已逾期）" : "")")
                            .font(.system(size: 11))
                            .foregroundColor(nextInfo.isOverdue ? .themeRed : .themeText3)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("已打 \(paidCount)/\(periodCount) 期")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(paidCount == periodCount ? .themeAccentDark : .themeText2)
                    Text("¥\(Int(paidAmount))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.themeText)
                    Text("水电结算 ¥\(Int(paidUtility))")
                        .font(.system(size: 10))
                        .foregroundColor(.themeText3)
                }

                VStack(spacing: 6) {
                    Button("详情") { onTap() }.macSecondaryButton()
                    Button("编辑") { onEdit() }.macSecondaryButton()
                    Button { onDelete() } label: { Image(systemName: "trash") }.macSecondaryButton()
                }
                .frame(width: 60)
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "EEEEEE"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新增 / 编辑包租合同

struct PayoutEditor: View {
    @ObservedObject var manager: DataManager
    let payout: PayoutRecord?
    let onClose: () -> Void

    @State private var roomNumber = ""
    @State private var managerName = ""
    @State private var unitType = ""
    @State private var leaseStartDate = Date()
    @State private var leaseEndDate = Date()
    @State private var leaseDuration = ""
    @State private var rentFreeDays = "0"
    @State private var monthlyRent = ""
    @State private var annualRent = ""
    @State private var deposit = ""
    @State private var waterMeterBase = "0"
    @State private var electricMeterBase = "0"
    @State private var rentDueDay = "1"
    @State private var paymentMethod = "月付"
    @State private var notes = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(payout == nil ? "新增包租合同" : "编辑包租合同").font(.system(size: 16, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("房号（如 2-1418）", text: $roomNumber)
                        TextField("包租人", text: $managerName)
                    }
                    HStack(spacing: 10) {
                        TextField("户型（如 单间/复式）", text: $unitType)
                        Picker("支付方式", selection: $paymentMethod) {
                            Text("月付").tag("月付")
                            Text("季付").tag("季付")
                            Text("半年付").tag("半年付")
                            Text("年付").tag("年付")
                        }
                        .pickerStyle(.segmented)
                    }
                    HStack(spacing: 10) {
                        DatePicker("起租日", selection: $leaseStartDate, displayedComponents: .date).labelsHidden()
                        DatePicker("到期日", selection: $leaseEndDate, displayedComponents: .date).labelsHidden()
                        TextField("租期描述", text: $leaseDuration)
                    }
                    HStack(spacing: 10) {
                        Text("免租期")
                        TextField("天", text: $rentFreeDays).frame(width: 60)
                        Text("付款日")
                        TextField("1-31", text: $rentDueDay).frame(width: 60)
                        Text("押金")
                        TextField("", text: $deposit).frame(width: 80)
                    }
                    HStack(spacing: 10) {
                        TextField("月租金（可留空，用年租倒算）", text: $monthlyRent)
                        TextField("年租金", text: $annualRent)
                    }
                    HStack(spacing: 10) {
                        Text("水表底数")
                        TextField("0", text: $waterMeterBase).frame(width: 70)
                        Text("电表底数")
                        TextField("0", text: $electricMeterBase).frame(width: 70)
                    }
                    TextField("备注", text: $notes)
                }
                .textFieldStyle(.roundedBorder)
            }
            if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 12)).foregroundColor(.themeDanger) }
            HStack {
                Text("保存后按支付方式生成打租记录").font(.system(size: 11)).foregroundColor(.themeText3)
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }.macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .onAppear {
            if let payout = payout {
                roomNumber = payout.roomNumber; managerName = payout.manager; unitType = payout.unitType
                leaseStartDate = payout.leaseStartDate; leaseEndDate = payout.leaseEndDate
                leaseDuration = payout.leaseDuration; rentFreeDays = "\(payout.rentFreeDays)"
                monthlyRent = payout.monthlyRent.map { "\(FormatKit.money($0))" } ?? ""
                annualRent = "\(FormatKit.money(payout.annualRent))"
                deposit = "\(FormatKit.money(payout.deposit))"
                waterMeterBase = "\(payout.waterMeterBase)"; electricMeterBase = "\(payout.electricMeterBase)"
                rentDueDay = "\(payout.rentDueDay)"; paymentMethod = payout.paymentMethod; notes = payout.notes
            }
        }
    }

    private func save() {
        guard !roomNumber.isEmpty else { errorMessage = "请填写房号"; return }
        guard let due = Int(rentDueDay), (1...31).contains(due) else { errorMessage = "付款日需为 1-31"; return }
        let mr = monthlyRent.isEmpty ? nil : Double(monthlyRent)
        let ar = annualRent.isEmpty ? (mr.map { $0 * 12 } ?? 0) : (Double(annualRent) ?? 0)
        let d = Double(deposit) ?? 0
        let w = Int(waterMeterBase) ?? 0
        let e = Int(electricMeterBase) ?? 0
        let freeDays = Int(rentFreeDays) ?? 0

        if let payout = payout {
            payout.roomNumber = roomNumber; payout.manager = managerName; payout.unitType = unitType
            payout.leaseStartDate = leaseStartDate; payout.leaseEndDate = leaseEndDate
            payout.leaseDuration = leaseDuration; payout.rentFreeDays = freeDays
            payout.monthlyRent = mr; payout.annualRent = ar; payout.deposit = d
            payout.waterMeterBase = w; payout.electricMeterBase = e
            payout.rentDueDay = due; payout.paymentMethod = paymentMethod; payout.notes = notes
            try? manager.mainContext.save()
            NotificationCenter.default.post(name: .macDataChanged, object: nil)
        } else {
            let record = manager.addPayout(roomNumber: roomNumber, manager: managerName, unitType: unitType,
                                           leaseStartDate: leaseStartDate, leaseEndDate: leaseEndDate,
                                           leaseDuration: leaseDuration, rentFreeDays: freeDays,
                                           monthlyRent: mr, annualRent: ar, deposit: d,
                                           waterMeterBase: w, electricMeterBase: e,
                                           rentDueDay: due, paymentMethod: paymentMethod, notes: notes)
            generatePayoutMonths(for: record)
        }
        MacToastCenter.show("已保存")
        onClose()
    }

    /// 按支付方式生成打租记录（对齐 iOS AddPayoutView）
    private func generatePayoutMonths(for record: PayoutRecord) {
        let periodCount: Int
        switch paymentMethod {
        case "季付": periodCount = 4
        case "半年付": periodCount = 2
        case "年付": periodCount = 1
        default: periodCount = 12
        }
        let periodMonths = 12 / periodCount
        let defaultAmount = (record.monthlyRent ?? 0) * Double(periodMonths)
        for i in 0..<periodCount {
            let month: Int
            switch paymentMethod {
            case "季付": month = (i + 1) * 3
            case "半年付": month = (i + 1) * 6
            case "年付": month = 12
            default: month = (i + 1) * 1
            }
            let rec = PayoutMonthRecord(month: month, amount: defaultAmount, isPaid: false)
            manager.mainContext.insert(rec)
            record.monthlyPayouts.append(rec)
        }
        try? manager.mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }
}

// MARK: - 包租详情

struct PayoutDetailView: View {
    @ObservedObject var manager: DataManager
    let payout: PayoutRecord
    let onClose: () -> Void

    private func periodMonth(for index: Int) -> Int {
        switch payout.paymentMethod {
        case "季付": return (index + 1) * 3
        case "半年付": return (index + 1) * 6
        case "年付": return 12
        default: return (index + 1) * 1
        }
    }
    private var sortedPayouts: [PayoutMonthRecord] {
        payout.monthlyPayouts.sorted { $0.month < $1.month }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("包租详情 · \(payout.roomNumber)").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("合同信息").font(.system(size: 13, weight: .bold)).foregroundColor(.themeText2)
                        row("包租人", payout.manager)
                        row("户型", payout.unitType)
                        row("租期", "\(FormatKit.dateStr(payout.leaseStartDate)) 至 \(FormatKit.dateStr(payout.leaseEndDate))（\(payout.leaseDuration)）")
                        row("免租期", "\(payout.rentFreeDays)天")
                        row("月租金", payout.monthlyRent.map { "¥\(Int($0))" } ?? "未设置")
                        row("年租金", "¥\(Int(payout.annualRent))")
                        row("押金", "¥\(Int(payout.deposit))")
                        row("支付方式", payout.paymentMethod)
                        row("付款日", "每月\(payout.rentDueDay)日")
                        row("水表底数", "\(payout.waterMeterBase)")
                        row("电表底数", "\(payout.electricMeterBase)")
                        if !payout.notes.isEmpty { row("备注", payout.notes) }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("打租记录（勾选即已付）").font(.system(size: 13, weight: .bold)).foregroundColor(.themeText2)
                        if sortedPayouts.isEmpty {
                            Text("暂无打租记录").font(.system(size: 12)).foregroundColor(.themeText3)
                        } else {
                            ForEach(sortedPayouts) { record in
                                HStack(spacing: 10) {
                                    Button {
                                        record.isPaid.toggle()
                                        record.paidDate = record.isPaid ? Date() : nil
                                        try? manager.mainContext.save()
                                        NotificationCenter.default.post(name: .macDataChanged, object: nil)
                                    } label: {
                                        Image(systemName: record.isPaid ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundColor(record.isPaid ? .themeAccentDark : .gray)
                                    }
                                    .buttonStyle(.plain)
                                    Text("\(record.month)月")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 60, alignment: .leading)
                                    Spacer()
                                    Text("¥\(FormatKit.money(record.amount))")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("水电结算记录").font(.system(size: 13, weight: .bold)).foregroundColor(.themeText2)
                        if payout.monthlyUtilityRecords.isEmpty {
                            Text("暂无结算记录").font(.system(size: 12)).foregroundColor(.themeText3)
                        } else {
                            ForEach(payout.monthlyUtilityRecords.sorted { $0.date > $1.date }) { rec in
                                HStack(spacing: 10) {
                                    Text(FormatKit.dateStr(rec.date)).font(.system(size: 12))
                                    Spacer()
                                    Text("水 ¥\(FormatKit.money(rec.waterAmount))").font(.system(size: 12))
                                    Text("电 ¥\(FormatKit.money(rec.electricAmount))").font(.system(size: 12))
                                    Text(rec.isSettled ? "已结算" : "未结算")
                                        .font(.system(size: 11))
                                        .foregroundColor(rec.isSettled ? .themeAccentDark : .themeText3)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    Spacer(minLength: 12)
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 640)
        .background(Color.themeBg)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).font(.system(size: 12)).foregroundColor(.themeText3).frame(width: 90, alignment: .leading)
            Text(value).font(.system(size: 13)).textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 1)
    }
}
