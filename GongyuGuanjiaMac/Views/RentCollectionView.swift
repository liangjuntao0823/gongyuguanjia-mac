import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 收租板块（对齐 iOS：交租日筛选 + 在租/退租 + 卡片排序 + 月度收租 + 水电结算计划）

struct RentCollectionView: View {
    @ObservedObject var manager: DataManager
    private static let xlsType = UTType(filenameExtension: "xls") ?? .data

    @State private var selectedDueDay: Int? = nil
    @State private var selectedStatus = 0 // 0 在租 / 1 退租
    @State private var searchText = ""
    @State private var showingAddProperty = false
    @State private var editingProperty: Property?
    @State private var selectedProperty: Property?
    @State private var terminatingProperty: Property?
    @State private var propertyToDelete: Property?
    @State private var propertyToRestore: Property?
    @State private var showUtility = false

    private var properties: [Property] { manager.properties.filter { $0.isDeleted != true } }

    private var registeredDueDays: [Int] {
        Array(Set(properties.filter { $0.isTerminated == (selectedStatus == 1) }.map { $0.rentDueDay })).sorted()
    }

    private var filteredProperties: [Property] {
        properties.filter { $0.isTerminated == (selectedStatus == 1) }
            .filter { selectedDueDay == nil || $0.rentDueDay == selectedDueDay }
            .filter {
                searchText.isEmpty ||
                $0.roomNumber.localizedCaseInsensitiveContains(searchText) ||
                $0.landlord.localizedCaseInsensitiveContains(searchText) ||
                $0.unitType.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { a, b in
                if a.isTerminated != b.isTerminated { return !a.isTerminated && b.isTerminated }
                // 在租：已收排最后，逾期靠前，其余按交租日临近排序
                let day = Calendar.current.component(.day, from: Date())
                let aPaid = a.isPaidForCard
                let bPaid = b.isPaidForCard
                if aPaid != bPaid { return !aPaid && bPaid }
                let aOverdue = !aPaid && a.rentDueDay < day
                let bOverdue = !bPaid && b.rentDueDay < day
                if aOverdue != bOverdue { return aOverdue && !bOverdue }
                if a.rentDueDay != b.rentDueDay { return a.rentDueDay < b.rentDueDay }
                return a.roomNumber < b.roomNumber
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("收租管理").font(.system(size: 20, weight: .bold))
                Spacer()
                TextField("搜索房号/房东/户型…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Button {
                    NotificationCenter.default.post(name: .macDataChanged, object: nil)
                    MacToastCenter.show("已刷新")
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                .macSecondaryButton()
                Button { exportToImage() } label: { Label("导出图片", systemImage: "photo") }
                    .macSecondaryButton()
                Button { exportToExcel() } label: { Label("导出 Excel", systemImage: "square.and.arrow.up") }
                    .macSecondaryButton()
                Button { showUtility = true } label: { Label("水电结算", systemImage: "bolt.fill") }
                    .macSecondaryButton()
                Button { showingAddProperty = true } label: { Label("新增房源", systemImage: "plus") }
                    .macPrimaryButton()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            // 交租日 chips
            if !registeredDueDays.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(nil, title: "全部")
                        ForEach(registeredDueDays, id: \.self) { day in chip(day, title: "\(day)号") }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }

            Picker("", selection: $selectedStatus) {
                Text("在租 \(properties.filter { !$0.isTerminated }.count)").tag(0)
                Text("退租 \(properties.filter { $0.isTerminated }.count)").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .labelsHidden()

            Divider().padding(.top, 8)

            if filteredProperties.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "banknote").font(.system(size: 40)).foregroundColor(.gray)
                    Text(selectedStatus == 0 ? "暂无在租房源" : "暂无退租房源").font(.system(size: 16)).foregroundColor(.themeText3)
                    if selectedStatus == 0 {
                        Button("新增房源") { showingAddProperty = true }.macSecondaryButton()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 600), spacing: 12)], spacing: 12) {
                        ForEach(filteredProperties) { prop in
                            if prop.isTerminated {
                                TerminatedPropertyRow(prop: prop,
                                                      onTap: { selectedProperty = prop },
                                                      onRestore: { propertyToRestore = prop },
                                                      onDelete: { propertyToDelete = prop })
                            } else {
                                PropertyRentCard(prop: prop,
                                                 onTap: { selectedProperty = prop },
                                                 onEdit: { editingProperty = prop },
                                                 onTerminate: { terminatingProperty = prop },
                                                 onDelete: { propertyToDelete = prop })
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showingAddProperty) { PropertyEditor(manager: manager, property: nil) { showingAddProperty = false } }
        .sheet(item: $editingProperty) { prop in PropertyEditor(manager: manager, property: prop) { editingProperty = nil } }
        .sheet(item: $selectedProperty) { prop in PropertyDetailView(manager: manager, property: prop) { selectedProperty = nil } }
        .sheet(item: $terminatingProperty) { prop in TerminationFormView(manager: manager, property: prop) { terminatingProperty = nil } }
        .sheet(isPresented: $showUtility) { UtilityView(manager: manager, onClose: { showUtility = false }) }
        .confirmationDialog("确定删除房源 \(propertyToDelete?.roomNumber ?? "") 吗？删除后可在回收站还原。",
                            isPresented: Binding(get: { propertyToDelete != nil }, set: { if !$0 { propertyToDelete = nil } })) {
            Button("确定删除", role: .destructive) {
                if let prop = propertyToDelete { manager.softDeleteProperty(prop); MacToastCenter.show("已删除") }
                propertyToDelete = nil
            }
            Button("取消", role: .cancel) { propertyToDelete = nil }
        }
        .confirmationDialog("确认还原退租房源 \(propertyToRestore?.roomNumber ?? "") ？",
                            isPresented: Binding(get: { propertyToRestore != nil }, set: { if !$0 { propertyToRestore = nil } })) {
            Button("确认还原") {
                if let prop = propertyToRestore { manager.restoreTerminatedProperty(prop); MacToastCenter.show("已还原为在租") }
                propertyToRestore = nil
            }
            Button("取消", role: .cancel) { propertyToRestore = nil }
        }
    }

    private func chip(_ day: Int?, title: String) -> some View {
        let isSelected = selectedDueDay == day
        return Button {
            selectedDueDay = day
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(isSelected ? Color.themeAccent : Color(red: 0.93, green: 0.94, blue: 0.95))
                .foregroundColor(isSelected ? .white : .themeText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 导出图片（对齐 iOS 收租导出图片）
    @MainActor
    private func exportToImage() {
        let headers = ["房号", "房东", "户型", "月租金", "交租日", "房源类型", "本月状态", "备注"]
        var rows: [[String]] = []
        let cal = Calendar.current
        let cy = cal.component(.year, from: Date())
        let cm = cal.component(.month, from: Date())
        for prop in filteredProperties {
            let current = prop.monthlyRentRecords.first { $0.year == cy && $0.month == cm }
            let status = current?.isPaid == true ? "已收" : (current != nil ? "未收" : "—")
            rows.append([prop.roomNumber, prop.landlord, prop.unitType, "¥\(Int(prop.rent))",
                         "\(max(1, prop.rentDueDay))号", prop.propertyType, status, prop.notes])
        }
        ExportImageService.exportTable(title: "收租管理", headers: headers, rows: rows, filename: "收租管理")
    }

    private func exportToExcel() {
        let headers = ["房号", "房东", "户型", "月租金", "交租日", "房源类型", "备注", "预存金额", "本月应收", "本月状态", "收租明细"]
        var rows: [[String]] = [headers]
        let cal = Calendar.current
        let cy = cal.component(.year, from: Date())
        let cm = cal.component(.month, from: Date())
        for prop in filteredProperties {
            let current = prop.monthlyRentRecords.first { $0.year == cy && $0.month == cm }
            let amount = current?.amount ?? prop.rent
            let status = current?.isPaid == true ? "已收" : "未收"
            let detail = prop.monthlyRentRecords.sorted { $0.year != $1.year ? $0.year < $1.year : $0.month < $1.month }
                .map { "\($0.year)年\($0.month)月:\($0.isPaid ? "已收" : "未收")¥\(Int($0.amount))" }.joined(separator: "；")
            rows.append([prop.roomNumber, prop.landlord, prop.unitType, "\(Int(prop.rent))", "\(prop.rentDueDay)", prop.propertyType, prop.notes, "\(Int(prop.prepayment))", "\(Int(amount))", status, detail])
        }
        let data = ExcelService.makeExcelHTML(rows: rows, sheetName: "收租管理")
        MacBridge.saveFile(defaultName: "收租管理_\(BackupTimestamp.string()).xls", allowedTypes: [Self.xlsType, .spreadsheet]) { url in
            guard let url = url else { return }
            try? data.write(to: url)
            MacToastCenter.show("已导出 \(rows.count - 1) 套房源")
        }
    }
}

// MARK: - 在租卡片

struct PropertyRentCard: View {
    let prop: Property
    let onTap: () -> Void
    let onEdit: () -> Void
    let onTerminate: () -> Void
    let onDelete: () -> Void

    private var paidMonthsCount: Int { prop.monthlyRentRecords.filter(\.isPaid).count }
    private var totalUtility: Double { prop.quarterlyUtilityRecords.reduce(0) { $0 + $1.total } }
    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var paid: Bool {
        prop.monthlyRentRecords.contains { $0.year == currentYear && $0.month == currentMonth && $0.isPaid }
    }
    // v1.2.4：徽标可见性修复——已收月份用深绿底白字（此前浅绿底+白字在白卡片上看不见）；未收用红底
    private var dueCircleColor: Color { paid ? Color(hex: "2E7D32") : Color.red.opacity(0.85) }
    private var isOverdue: Bool { max(1, prop.rentDueDay) < Calendar.current.component(.day, from: Date()) && !paid }

    /// 桌面端卡片：头部（交租日徽标+房号+操作）→ 户型/状态行 → 信息行 → 状态行
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // 头部行
                HStack(spacing: 12) {
                    VStack(spacing: 3) {
                        Text("\(max(1, prop.rentDueDay))号")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(dueCircleColor)
                            .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prop.roomNumber)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.themeText)
                        Text(prop.landlord)
                            .font(.system(size: 13))
                            .foregroundColor(.themeText2)
                    }
                    Spacer()
                    actionColumn
                }
                Divider()
                // 户型/状态行
                HStack(spacing: 8) {
                    // v1.2.11：仅保留圆形类型标 + 户型，删除重复的「管理/托管」文字与 chip
                    Text(prop.typeChar)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(prop.typeColor)
                        .frame(width: 20, height: 20)
                        .background(prop.typeBgColor)
                        .clipShape(Circle())
                    Text(prop.unitType).font(.system(size: 13)).foregroundColor(.themeText2)
                    Spacer()
                    // v1.2.10：收租进度条（已收/总期数），更直观
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("已收 \(paidMonthsCount)/\(prop.monthlyRentRecords.count) 期")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.themeAccentDark)
                        ProgressView(value: Double(paidMonthsCount), total: Double(max(prop.monthlyRentRecords.count, 1)))
                            .progressViewStyle(.linear)
                            .tint(Color(hex: "2E7D32"))
                            .frame(width: 90)
                    }
                    if isOverdue {
                        Text("逾期")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                // v1.2.4 信息区：三栏网格（租金/押预 | 租期 | 本月水电），桌面大屏更充实
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("¥\(Int(prop.rent))/月")
                            .font(.system(size: 17, weight: .bold)).foregroundColor(.themeDanger)
                        Text("押\(Int(prop.deposit))" + (prop.prepayment > 0 ? " · 预存\(Int(prop.prepayment))" : ""))
                            .font(.system(size: 12)).foregroundColor(.themeText3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("租期").font(.system(size: 11)).foregroundColor(.themeText3)
                        Text(prop.leaseStart.isEmpty ? "未出租" : "\(prop.leaseStart) 至 \(prop.leaseEnd)")
                            .font(.system(size: 12)).foregroundColor(prop.leaseStart.isEmpty ? .themeText3 : .themeText2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("累积水电").font(.system(size: 11)).foregroundColor(.themeText3)
                        Text("¥\(Int(totalUtility))")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.themeText)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // 状态行
                HStack(spacing: 10) {
                    Text(paid ? "本月已收" : "本月待收")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(paid ? .themeAccentDark : .themeRed)
                    if !prop.notes.isEmpty {
                        Text(prop.notes)
                            .font(.system(size: 12))
                            .foregroundColor(.themeText3)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOverdue ? Color.red.opacity(0.55) : Color(hex: "EEEEEE"), lineWidth: isOverdue ? 1.5 : 1)
            )
            .overlay(
                // 左侧类型色条：一眼区分经营类型
                HStack { Rectangle().fill(prop.typeColor).frame(width: 4); Spacer() }
            )
        }
        .buttonStyle(.plain)
    }

    private var actionColumn: some View {
        HStack(spacing: 6) {
            Button("编辑") { onEdit() }.macSecondaryButton()
            Button("退租") { onTerminate() }.macSecondaryButton()
            Button { onDelete() } label: { Image(systemName: "trash") }.macSecondaryButton()
        }
    }
}

// MARK: - 退租卡片

struct TerminatedPropertyRow: View {
    let prop: Property
    let onTap: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var dateText: String {
        prop.terminationDate.map { FormatKit.dateStr($0) } ?? "未填写"
    }
    private var paidMonthsCount: Int { prop.monthlyRentRecords.filter(\.isPaid).count }

    /// 桌面端退租卡片：头部（退租标记+房号+操作）→ 信息行 → 状态行
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 16))
                        .foregroundColor(.themeText3)
                        .frame(width: 42, height: 42)
                        .background(Color(red: 0.93, green: 0.94, blue: 0.95))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prop.roomNumber)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.themeText)
                        Text("\(dateText) 退租")
                            .font(.system(size: 12))
                            .foregroundColor(.themeText3)
                    }
                    Spacer()
                    actionColumn
                }
                Divider()
                HStack(spacing: 14) {
                    Text(prop.landlord).font(.system(size: 13)).foregroundColor(.themeText2)
                    Text(prop.unitType).font(.system(size: 13)).foregroundColor(.themeText2)
                    Text("¥\(Int(prop.rent))/月").font(.system(size: 14, weight: .semibold)).foregroundColor(.themeText)
                    Spacer()
                    Text("已收\(paidMonthsCount)个月")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.themeAccentDark)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color(hex: "E8F5E9"))
                        .clipShape(Capsule())
                }
                if !prop.terminationReason.isEmpty {
                    Text("退租原因：\(prop.terminationReason)")
                        .font(.system(size: 12))
                        .foregroundColor(.themeText3)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .background(Color(red: 0.985, green: 0.985, blue: 0.985))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "EEEEEE"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var actionColumn: some View {
        HStack(spacing: 6) {
            Button("还原") { onRestore() }.macSecondaryButton()
            Button { onDelete() } label: { Image(systemName: "trash") }.macSecondaryButton()
        }
    }
}

// MARK: - 月度收租行

struct MonthRentRow: View {
    @ObservedObject var manager: DataManager
    let prop: Property
    let record: RentMonthRecord
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Button {
                record.isPaid.toggle()
                record.paidDate = record.isPaid ? Date() : nil
                try? manager.mainContext.save()
                NotificationCenter.default.post(name: .macDataChanged, object: nil)
            } label: {
                Image(systemName: record.isPaid ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundColor(record.isPaid ? .themeAccentDark : .gray)
            }
            .buttonStyle(.plain)
            Text(label).font(.system(size: 15)).foregroundColor(.themeText)
            Spacer()
            Text("¥\(FormatKit.money(record.amount))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(record.isPaid ? .themeText2 : .themeText)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 水电结算计划行

struct UtilityPlanRow: View {
    @ObservedObject var manager: DataManager
    let prop: Property
    let record: UtilitySettlementRecord
    let onDataChanged: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(record.statement.isEmpty ? "\(record.year)年\(record.frequency == "monthly" ? "\(record.period)月" : "\(record.period)季度")" : record.statement)
                .font(.system(size: 15))
            Spacer()
            Text("电 ¥\(FormatKit.money(record.electricAmount))")
                .font(.system(size: 14))
            Text("水 ¥\(FormatKit.money(record.waterAmount))")
                .font(.system(size: 14))
            Text("结余 ¥\(FormatKit.money(record.balance))")
                .font(.system(size: 14))
                .foregroundColor(record.balance >= 0 ? .themeAccentDark : .themeRed)
            Button {
                record.isSettled.toggle()
                record.settledAt = record.isSettled ? Date() : nil
                try? manager.mainContext.save()
                NotificationCenter.default.post(name: .macDataChanged, object: nil)
                onDataChanged()
            } label: {
                Text(record.isSettled ? "已结算" : "未结算")
                    .font(.system(size: 13))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(record.isSettled ? Color(hex: "E8F5E9") : Color(hex: "F0F0F0"))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 房源详情

struct PropertyDetailView: View {
    @ObservedObject var manager: DataManager
    let property: Property
    let onClose: () -> Void

    @State private var showTerminationForm = false
    @State private var showEditProperty = false
    @State private var showRentPlanEditor = false
    @State private var showUtilityPlanEditor = false
    @State private var showUtility = false
    @State private var dataRefreshID = UUID()

    private var sortedRecords: [RentMonthRecord] {
        property.monthlyRentRecords.sorted { $0.year != $1.year ? $0.year < $1.year : $0.month < $1.month }
    }
    private var cachedUtilityRecords: [UtilitySettlementRecord] {
        property.utilitySettlementRecords.sorted { $0.year != $1.year ? $0.year < $1.year : $0.period < $1.period }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("房源详情 · \(property.roomNumber)").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("编辑") { showEditProperty = true }.macSecondaryButton()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // v1.2.10 概览头卡：房号/状态/租金/押预 一眼可见
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text(property.roomNumber)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.themeText)
                                Text(property.isTerminated ? "已退租" : "在租")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(property.isTerminated ? Color.gray : Color.themeAccent)
                                    .clipShape(Capsule())
                            }
                            Text("\(property.typeDisplayName) · \(property.unitType) · 房东 \(property.landlord)")
                                .font(.system(size: 13)).foregroundColor(.themeText2)
                            Text("交租日：每月\(property.rentDueDay)号 · \(property.propertyType)")
                                .font(.system(size: 12)).foregroundColor(.themeText3)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("¥\(Int(property.rent))/月")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.themeDanger)
                            Text("押¥\(Int(property.deposit))\(property.prepayment > 0 ? " · 预存¥\(Int(property.prepayment))" : "")")
                                .font(.system(size: 13)).foregroundColor(.themeText2)
                            if !property.notes.isEmpty {
                                Text(property.notes)
                                    .font(.system(size: 12)).foregroundColor(.themeText3).lineLimit(1)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(red: 0.975, green: 0.978, blue: 0.98))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "E8E8E8"), lineWidth: 1))

                    if property.isTerminated {
                        section("退租信息") {
                            row("退租时间", property.terminationDate.map { FormatKit.dateStr($0) } ?? "未填写")
                            row("退租原因", property.terminationReason.isEmpty ? "未填写" : property.terminationReason)
                            row("押金退还", property.depositRefundStatus.isEmpty ? "未填写" : property.depositRefundStatus)
                            row("房间损坏", property.roomDamageStatus.isEmpty ? "未填写" : property.roomDamageStatus)
                            row("水电结算", property.utilitySettlementStatus.isEmpty ? "未填写" : property.utilitySettlementStatus)
                            row("退租人", property.terminationPerson.isEmpty ? "未填写" : property.terminationPerson)
                            row("联系电话", property.terminationPhone.isEmpty ? "未填写" : property.terminationPhone)
                        }
                    }
                    section("房源信息") {
                        row("房号", property.roomNumber)
                        row("房东", property.landlord)
                        row("户型", property.unitType)
                        row("房源类型", property.typeDisplayName)
                        row("租金", "¥\(Int(property.rent))/月")
                        row("押金", "¥\(Int(property.deposit))")
                        row("预存", "¥\(Int(property.prepayment))")
                        row("起止期", property.leaseStart.isEmpty ? "未出租" : "\(property.leaseStart) 至 \(property.leaseEnd)")
                        if !property.leaseDuration.isEmpty { row("租期", property.leaseDuration) }
                        row("交租日", "每月\(property.rentDueDay)号")
                        if !property.notes.isEmpty { row("备注", property.notes) }
                    }

                    sectionWithAction("月度收租（打勾后金额锁定）", actionTitle: "编辑计划", action: { showRentPlanEditor = true }) {
                        if sortedRecords.isEmpty {
                            Text("暂无收租记录，点「编辑计划」生成").font(.system(size: 14)).foregroundColor(.themeText3)
                        } else {
                            ForEach(sortedRecords) { record in
                                MonthRentRow(manager: manager, prop: property, record: record,
                                             label: "\(record.year)年\(record.month)月\(property.rentDueDay)日")
                            }
                        }
                    }
                    .id(dataRefreshID)

                    sectionWithAction("水电结算（金额可输入，取消结算需确认）", actionTitle: "编辑计划", action: { showUtilityPlanEditor = true }) {
                        if cachedUtilityRecords.isEmpty {
                            Text("暂无结算计划，请编辑房源后保存生成").font(.system(size: 14)).foregroundColor(.themeText3)
                        } else {
                            ForEach(cachedUtilityRecords) { record in
                                UtilityPlanRow(manager: manager, prop: property, record: record, onDataChanged: { dataRefreshID = UUID() })
                            }
                        }
                    }

                    section("水电底数") {
                        row("水表底数", "\(property.waterMeterBase)")
                        row("电表底数", "\(property.electricMeterBase)")
                    }

                    HStack(spacing: 10) {
                        Button("水电工具") { showUtility = true }.macSecondaryButton()
                        if property.isTerminated {
                            Button("还原在租") {
                                manager.restoreTerminatedProperty(property)
                                MacToastCenter.show("已还原为在租")
                            }.macSecondaryButton()
                        } else {
                            Button("退租") { showTerminationForm = true }.macSecondaryButton()
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 640)
        .background(Color.themeBg)
        .sheet(isPresented: $showTerminationForm) {
            TerminationFormView(manager: manager, property: property) { showTerminationForm = false }
        }
        .sheet(isPresented: $showEditProperty) {
            PropertyEditor(manager: manager, property: property) { showEditProperty = false }
        }
        .sheet(isPresented: $showRentPlanEditor) {
            RentPlanEditor(manager: manager, property: property) { showRentPlanEditor = false }
        }
        .sheet(isPresented: $showUtilityPlanEditor) {
            UtilityPlanEditor(manager: manager, property: property) { showUtilityPlanEditor = false }
        }
        .sheet(isPresented: $showUtility) { UtilityView(manager: manager) }
    }

    // v1.2.10：分区卡片化（白色卡片 + 圆角 + 描边），替代单一文字连排
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.themeText2)
            VStack(spacing: 4) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "EDEDED"), lineWidth: 1))
        }
    }
    private func sectionWithAction(_ title: String, actionTitle: String, action: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.themeText2)
                Spacer()
                Button(actionTitle) { action() }.macSecondaryButton()
            }
            VStack(spacing: 4) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "EDEDED"), lineWidth: 1))
        }
    }
    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).font(.system(size: 13)).foregroundColor(.themeText3)
                .frame(width: 92, alignment: .leading)
            Text(value).font(.system(size: 14)).foregroundColor(.themeText).textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 新增 / 编辑房源

struct PropertyEditor: View {
    @ObservedObject var manager: DataManager
    let property: Property?
    let onClose: () -> Void

    @State private var roomNumber = ""
    @State private var landlord = ""
    @State private var unitType = ""
    @State private var rent = ""
    @State private var deposit = ""
    @State private var prepayment = ""
    @State private var leaseStart = ""
    @State private var leaseEnd = ""
    @State private var leaseDuration = ""
    @State private var rentDueDay = "1"
    @State private var waterMeterBase = "0"
    @State private var electricMeterBase = "0"
    @State private var propertyType = "管理"
    @State private var notes = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(property == nil ? "新增收租房源" : "编辑房源").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("房号（如 2-1418）", text: $roomNumber)
                        TextField("房东", text: $landlord)
                    }
                    HStack(spacing: 10) {
                        TextField("户型（如 单间/复式）", text: $unitType)
                        Picker("类型", selection: $propertyType) {
                            Text("管理").tag("管理")
                            Text("包租").tag("包租")
                            Text("托管").tag("托管")
                        }
                        .pickerStyle(.segmented)
                    }
                    HStack(spacing: 10) {
                        TextField("月租金", text: $rent)
                        TextField("押金", text: $deposit)
                        TextField("预存金额", text: $prepayment)
                    }
                    HStack(spacing: 10) {
                        TextField("租期开始（如 2026.10.1）", text: $leaseStart)
                        TextField("租期结束（如 2027.10.1）", text: $leaseEnd)
                        TextField("租期描述（如 一年）", text: $leaseDuration)
                    }
                    HStack(spacing: 10) {
                        Text("交租日")
                        TextField("1-31", text: $rentDueDay).frame(width: 60)
                        Text("水表底数")
                        TextField("0", text: $waterMeterBase).frame(width: 70)
                        Text("电表底数")
                        TextField("0", text: $electricMeterBase).frame(width: 70)
                    }
                    TextField("备注", text: $notes)
                }
                .textFieldStyle(.roundedBorder)
            }
            if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 14)).foregroundColor(.themeDanger) }
            HStack {
                Text("保存后自动生成收租计划与水电结算计划").font(.system(size: 13)).foregroundColor(.themeText3)
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }.macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 520, height: 440)
        .onAppear {
            if let property = property {
                roomNumber = property.roomNumber; landlord = property.landlord; unitType = property.unitType
                rent = "\(FormatKit.money(property.rent))"; deposit = "\(FormatKit.money(property.deposit))"
                prepayment = "\(FormatKit.money(property.prepayment))"
                leaseStart = property.leaseStart; leaseEnd = property.leaseEnd; leaseDuration = property.leaseDuration
                rentDueDay = "\(property.rentDueDay)"
                waterMeterBase = "\(property.waterMeterBase)"; electricMeterBase = "\(property.electricMeterBase)"
                propertyType = property.typeDisplayName; notes = property.notes
            }
        }
    }

    private func save() {
        guard !roomNumber.isEmpty else { errorMessage = "请填写房号"; return }
        guard let r = Double(rent), r >= 0 else { errorMessage = "租金无效"; return }
        guard let due = Int(rentDueDay), (1...31).contains(due) else { errorMessage = "交租日需为 1-31"; return }
        let d = Double(deposit) ?? 0
        let p = Double(prepayment) ?? 0
        let w = Int(waterMeterBase) ?? 0
        let e = Int(electricMeterBase) ?? 0
        if let property = property {
            property.roomNumber = roomNumber; property.landlord = landlord; property.unitType = unitType
            property.rent = r; property.deposit = d; property.prepayment = p
            property.leaseStart = leaseStart; property.leaseEnd = leaseEnd; property.leaseDuration = leaseDuration
            property.rentDueDay = due; property.waterMeterBase = w; property.electricMeterBase = e
            property.propertyType = propertyType; property.notes = notes
            try? manager.mainContext.save()
            NotificationCenter.default.post(name: .macDataChanged, object: nil)
        } else {
            let prop = manager.addProperty(roomNumber: roomNumber, landlord: landlord, unitType: unitType,
                                           rent: r, deposit: d, prepayment: p,
                                           leaseStart: leaseStart, leaseEnd: leaseEnd, leaseDuration: leaseDuration,
                                           rentDueDay: due, waterMeterBase: w, electricMeterBase: e,
                                           propertyType: propertyType, notes: notes)
            generatePlans(for: prop)
        }
        MacToastCenter.show("已保存")
        onClose()
    }

    /// 首次生成收租计划 + 水电结算计划（对齐 iOS AddPropertyView）
    private func generatePlans(for prop: Property) {
        let cal = Calendar.current
        let now = Date()
        // 收租计划：未来 12 个月
        for i in 0..<12 {
            let date = cal.date(byAdding: .month, value: i, to: now) ?? now
            let record = RentMonthRecord(year: cal.component(.year, from: date),
                                         month: cal.component(.month, from: date),
                                         amount: prop.rent + prop.prepayment, isPaid: false)
            manager.mainContext.insert(record)
            prop.monthlyRentRecords.append(record)
        }
        // 水电结算计划（季度）
        for q in 1...4 {
            let record = UtilitySettlementRecord(year: cal.component(.year, from: now), period: q, frequency: "quarterly")
            manager.mainContext.insert(record)
            prop.utilitySettlementRecords.append(record)
        }
        try? manager.mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }
}

// MARK: - 退租表单

struct TerminationFormView: View {
    @ObservedObject var manager: DataManager
    let property: Property
    let onClose: () -> Void

    @State private var date = Date()
    @State private var reason = ""
    @State private var depositRefund = ""
    @State private var roomDamage = ""
    @State private var utilitySettlement = ""
    @State private var person = ""
    @State private var phone = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("退租 · \(property.roomNumber)").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("退租时间", selection: $date, displayedComponents: .date)
                    TextField("退租原因", text: $reason)
                    TextField("押金退还", text: $depositRefund)
                    TextField("房间损坏", text: $roomDamage)
                    TextField("水电结算", text: $utilitySettlement)
                    HStack(spacing: 10) {
                        TextField("退租人", text: $person)
                        TextField("联系电话", text: $phone)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 14)).foregroundColor(.themeDanger) }
            HStack {
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("确认退租") { save() }.macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 440, height: 380)
    }

    private func save() {
        guard !reason.isEmpty else { errorMessage = "请填写退租原因"; return }
        manager.terminateProperty(property, date: date, reason: reason,
                                  depositRefund: depositRefund, roomDamage: roomDamage,
                                  utilitySettlement: utilitySettlement, person: person, phone: phone)
        MacToastCenter.show("已标记退租")
        onClose()
    }
}

// MARK: - 收租计划编辑器（批量）

struct RentPlanEditor: View {
    @ObservedObject var manager: DataManager
    let property: Property
    let onClose: () -> Void

    @State private var drafts: [RentPlanDraft] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("编辑收租计划 · \(property.roomNumber)").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }
            List {
                ForEach($drafts) { $d in
                    HStack(spacing: 10) {
                        DatePicker("", selection: $d.date, displayedComponents: .date).labelsHidden().frame(width: 130)
                        TextField("金额", text: $d.amount).textFieldStyle(.roundedBorder).frame(width: 90)
                        Toggle("已收", isOn: $d.isPaid)
                    }
                }
                .onDelete { drafts.remove(atOffsets: $0) }
            }
            HStack {
                Button {
                    drafts.append(RentPlanDraft(date: Date(), amount: String(Int(property.rent + property.prepayment)), isPaid: false))
                } label: { Label("新增收租计划", systemImage: "plus") }
                .macSecondaryButton()
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }.macPrimaryButton()
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
        .onAppear {
            drafts = property.monthlyRentRecords
                .sorted { $0.year != $1.year ? $0.year < $1.year : $0.month < $1.month }
                .map {
                    RentPlanDraft(id: $0.id, date: Self.dateFor(year: $0.year, month: $0.month, dueDay: property.rentDueDay),
                                  amount: String(Int($0.amount)), isPaid: $0.isPaid)
                }
        }
    }

    private static func dateFor(year: Int, month: Int, dueDay: Int) -> Date {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = dueDay
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func save() {
        for record in property.monthlyRentRecords where !record.isPaid {
            manager.mainContext.delete(record)
        }
        property.monthlyRentRecords.removeAll { !$0.isPaid }
        let cal = Calendar.current
        for d in drafts {
            let y = cal.component(.year, from: d.date)
            let m = cal.component(.month, from: d.date)
            let record = RentMonthRecord(id: d.id == UUID() ? UUID() : d.id, year: y, month: m,
                                         amount: Double(d.amount) ?? 0, isPaid: d.isPaid)
            record.paidDate = d.isPaid ? d.date : nil
            manager.mainContext.insert(record)
            property.monthlyRentRecords.append(record)
        }
        try? manager.mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
        MacToastCenter.show("已保存收租计划")
        onClose()
    }
}

struct RentPlanDraft: Identifiable {
    var id: UUID = UUID()
    var date: Date
    var amount: String
    var isPaid: Bool
}

// MARK: - 水电计划编辑器（批量）

struct UtilityPlanEditor: View {
    @ObservedObject var manager: DataManager
    let property: Property
    let onClose: () -> Void

    @State private var drafts: [UtilityPlanDraft] = []

    private var frequency: String { property.utilitySettlementFrequency == "monthly" ? "monthly" : "quarterly" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("编辑水电结算计划 · \(property.roomNumber)").font(.system(size: 17, weight: .bold))
                Text(frequency == "monthly" ? "（按月）" : "（按季）")
                    .font(.system(size: 13)).foregroundColor(.themeText3)
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }
            List {
                ForEach($drafts) { $d in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            DatePicker("结算日期", selection: $d.date, displayedComponents: .date)
                                .labelsHidden()
                                .frame(width: 150)
                            TextField("电费", text: $d.electricAmount).textFieldStyle(.roundedBorder).frame(width: 80)
                            TextField("水费", text: $d.waterAmount).textFieldStyle(.roundedBorder).frame(width: 80)
                            TextField("结余", text: $d.balance).textFieldStyle(.roundedBorder).frame(width: 80)
                            Toggle("已结算", isOn: $d.isSettled)
                        }
                        TextField("结算单（备注）", text: $d.statement)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .onDelete { drafts.remove(atOffsets: $0) }
            }
            HStack {
                Button {
                    let base = drafts.last?.date ?? Date()
                    let next = Calendar.current.date(byAdding: .month, value: 1, to: base) ?? base
                    drafts.append(UtilityPlanDraft(date: next, frequency: frequency))
                } label: { Label("新增\(frequency == "monthly" ? "月" : "季")度计划", systemImage: "plus") }
                .macSecondaryButton()
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }.macPrimaryButton()
            }
        }
        .padding(16)
        .frame(width: 640, height: 440)
        .onAppear {
            drafts = property.utilitySettlementRecords
                .sorted {
                    let a = $0.dueDate ?? .distantFuture, b = $1.dueDate ?? .distantFuture
                    return a < b
                }
                .map {
                    UtilityPlanDraft(id: $0.id,
                                     date: $0.dueDate ?? Self.dateFor(year: $0.year, period: $0.period, frequency: $0.frequency),
                                     frequency: $0.frequency,
                                     electricAmount: $0.electricAmount == 0 ? "" : String(Int($0.electricAmount)),
                                     waterAmount: $0.waterAmount == 0 ? "" : String(Int($0.waterAmount)),
                                     balance: $0.balance == 0 ? "" : String(Int($0.balance)),
                                     isSettled: $0.isSettled, statement: $0.statement)
                }
        }
    }

    private static func dateFor(year: Int, period: Int, frequency: String) -> Date {
        let month = frequency == "monthly" ? period : (period - 1) * 3 + 1
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func save() {
        for record in property.utilitySettlementRecords {
            manager.mainContext.delete(record)
        }
        property.utilitySettlementRecords.removeAll()
        let cal = Calendar.current
        for d in drafts {
            let y = cal.component(.year, from: d.date)
            let m = cal.component(.month, from: d.date)
            let period = d.frequency == "monthly" ? m : ((m - 1) / 3 + 1)
            let record = UtilitySettlementRecord(id: d.id == UUID() ? UUID() : d.id, year: y, period: period,
                                                 frequency: d.frequency,
                                                 electricAmount: Double(d.electricAmount) ?? 0,
                                                 waterAmount: Double(d.waterAmount) ?? 0,
                                                 balance: Double(d.balance) ?? 0,
                                                 isSettled: d.isSettled, statement: d.statement,
                                                 settledAt: d.isSettled ? Date() : nil,
                                                 dueDate: d.date)
            manager.mainContext.insert(record)
            property.utilitySettlementRecords.append(record)
        }
        try? manager.mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
        MacToastCenter.show("已保存水电计划")
        onClose()
    }
}

struct UtilityPlanDraft: Identifiable {
    var id: UUID = UUID()
    var date: Date
    var frequency: String
    var electricAmount: String = "0"
    var waterAmount: String = "0"
    var balance: String = "0"
    var isSettled: Bool = false
    var statement: String = ""

    init(id: UUID = UUID(), date: Date = Date(), frequency: String = "quarterly",
         electricAmount: String = "0", waterAmount: String = "0", balance: String = "0",
         isSettled: Bool = false, statement: String = "") {
        self.id = id; self.date = date; self.frequency = frequency
        self.electricAmount = electricAmount; self.waterAmount = waterAmount; self.balance = balance
        self.isSettled = isSettled; self.statement = statement
    }
}
