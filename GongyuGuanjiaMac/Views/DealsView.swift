import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 成交记录（对齐 iOS：成交合同 + 杂项收入 + 杂项支出）

struct DealsView: View {
    @ObservedObject var manager: DataManager

    private static let xlsType = UTType(filenameExtension: "xls") ?? .data
    private static let csvType = UTType(filenameExtension: "csv") ?? .data

    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var selectedYear: Int? = nil     // 年筛选（nil=全部，iOS WheelYearMonthPicker 对齐）
    @State private var selectedMonth: Int? = nil    // 月筛选（nil=全部）
    @State private var selection: UUID? = nil        // 定位高亮（Table 选中）
    @State private var highlightedID: UUID? = nil    // 杂收杂支行点击高亮
    @State private var highlightClearTask: Task<Void, Never>?
    @State private var showingAddDeal = false
    @State private var viewingDeal: DealRecord?
    @State private var editingDeal: DealRecord?
    @State private var editingIncome: MiscIncome?
    @State private var editingExpense: MiscExpense?

    /// 年/月过滤（nil=全部；年筛选可选列表内出现过的年份）
    private var availableYears: [Int] {
        var set = Set<Int>()
        for d in manager.deals where d.isDeleted != true { set.insert(Calendar.current.component(.year, from: d.date)) }
        for i in manager.miscIncomes where i.isDeleted != true { set.insert(Calendar.current.component(.year, from: i.date)) }
        for e in manager.miscExpenses where e.isDeleted != true { set.insert(Calendar.current.component(.year, from: e.date)) }
        return set.sorted(by: >)
    }
    private func yearMatch(_ d: Date) -> Bool {
        if let y = selectedYear, Calendar.current.component(.year, from: d) != y { return false }
        if let m = selectedMonth, Calendar.current.component(.month, from: d) != m { return false }
        return true
    }
    private var deals: [DealRecord] {
        let list = manager.deals.filter { $0.isDeleted != true && yearMatch($0.date) }
        if searchText.isEmpty { return list.sorted { $0.date > $1.date } }
        return list.filter {
            $0.roomNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.landlord.localizedCaseInsensitiveContains(searchText) ||
            $0.unitType.localizedCaseInsensitiveContains(searchText) ||
            $0.manager.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.date > $1.date }
    }
    private var incomes: [MiscIncome] {
        let list = manager.miscIncomes.filter { $0.isDeleted != true && yearMatch($0.date) }
        if searchText.isEmpty { return list.sorted { $0.date > $1.date } }
        return list.filter {
            $0.item.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.date > $1.date }
    }
    private var expenses: [MiscExpense] {
        let list = manager.miscExpenses.filter { $0.isDeleted != true && yearMatch($0.date) }
        if searchText.isEmpty { return list.sorted { $0.date > $1.date } }
        return list.filter {
            $0.item.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 第一行：标题 + 搜索 + 年/月筛选
            HStack(spacing: 10) {
                Text("成交管理")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                TextField("搜索…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                // 年/月筛选（对齐 iOS WheelYearMonthPicker）
                Picker("年", selection: $selectedYear) {
                    Text("全部年份").tag(nil as Int?)
                    ForEach(availableYears, id: \.self) { y in Text("\(y)年").tag(Int?(y)) }
                }
                .frame(width: 110)
                Picker("月", selection: $selectedMonth) {
                    Text("全部月份").tag(nil as Int?)
                    ForEach(1...12, id: \.self) { m in Text("\(m)月").tag(Int?(m)) }
                }
                .frame(width: 100)
                if selectedYear != nil || selectedMonth != nil {
                    Button {
                        selectedYear = nil; selectedMonth = nil
                    } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.themeText3) }
                        .buttonStyle(.plain).help("清除筛选")
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            // 第二行：操作按钮组（v1.2.10 独立成行，避免挤压错乱）
            HStack(spacing: 10) {
                Button { exportToImage() } label: { Label("导出图片", systemImage: "photo") }
                    .macSecondaryButton()
                Button { exportToExcel() } label: { Label("导出 Excel", systemImage: "tablecells") }
                    .macSecondaryButton()
                Button { exportTemplate() } label: { Label("模板", systemImage: "doc.text") }
                    .macSecondaryButton()
                Button { importFromFile() } label: { Label("导入", systemImage: "square.and.arrow.down") }
                    .macSecondaryButton()
                Spacer()
                Button {
                    if selectedTab == 0 { showingAddDeal = true }
                    else if selectedTab == 1 { editingIncome = MiscIncome() }
                    else { editingExpense = MiscExpense() }
                } label: {
                    Label(selectedTab == 0 ? "新增成交" : (selectedTab == 1 ? "新增收入" : "新增支出"), systemImage: "plus")
                }
                .macPrimaryButton()
            }
            .padding(.horizontal, 16).padding(.bottom, 10)

            Picker("", selection: $selectedTab) {
                Text("成交 \(deals.count)").tag(0)
                Text("杂项收入 \(incomes.count)").tag(1)
                Text("杂项支出 \(expenses.count)").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .labelsHidden()

            Divider().padding(.top, 10)

            if selectedTab == 0 {
                dealList
            } else if selectedTab == 1 {
                miscList(isIncome: true)
            } else {
                miscList(isIncome: false)
            }
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showingAddDeal) {
            DealEditor(manager: manager, deal: nil,
                      onClose: { showingAddDeal = false },
                      onSaved: { record in
                selection = record.id
                highlightedID = record.id
                scheduleHighlightClear()
            })
        }
        .sheet(item: $viewingDeal) { deal in DealDetailView(manager: manager, deal: deal) { viewingDeal = nil } }
        .sheet(item: $editingDeal) { deal in DealEditor(manager: manager, deal: deal) { editingDeal = nil } }
        .sheet(item: $editingIncome) { inc in
            MiscEditor(manager: manager, income: inc, isIncome: true) { editingIncome = nil }
        }
        .sheet(item: $editingExpense) { exp in
            MiscEditor(manager: manager, expense: exp, isIncome: false) { editingExpense = nil }
        }
        // v1.2.15：杂项删除确认改为 AppKit 原生 MacAlert（移除 SwiftUI confirmationDialog——多弹窗修饰符共存会互相屏蔽导致删除无反应）
    }

    // MARK: 成交列表
    private var dealList: some View {
        Group {
            if deals.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text").font(.system(size: 40, weight: .medium)).foregroundColor(.gray)
                    Text("暂无成交记录").font(.system(size: 16, weight: .medium)).foregroundColor(.themeText3)
                    Button("新增成交") { showingAddDeal = true }.macSecondaryButton()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(deals, selection: $selection) {
                    TableColumn("成交日期") { deal in
                        dealCell(deal) { Text(FormatKit.dateStr(deal.date)) }
                    }.width(95)
                    TableColumn("房号") { deal in
                        dealCell(deal) { Text(deal.roomNumber) }
                    }.width(80)
                    TableColumn("房东") { deal in
                        dealCell(deal) { Text(deal.landlord) }
                    }.width(70)
                    TableColumn("户型") { deal in
                        dealCell(deal) { Text(deal.unitType) }
                    }.width(70)
                    TableColumn("租期") { deal in
                        dealCell(deal) { Text(deal.leaseDuration) }
                    }.width(70)
                    TableColumn("租金/月") { deal in
                        dealCell(deal) { Text("¥\(FormatKit.money(deal.rent))") }
                    }.width(90)
                    TableColumn("押金") { deal in
                        dealCell(deal) { Text("¥\(FormatKit.money(deal.deposit))") }
                    }.width(80)
                    TableColumn("中介费") { deal in
                        dealCell(deal) { Text("¥\(FormatKit.money(deal.totalFee))") }
                    }.width(80)
                    TableColumn("经办人") { deal in
                        dealCell(deal) { Text(deal.manager) }
                    }.width(70)
                    TableColumn("操作") { deal in
                        HStack(spacing: 6) {
                            Button("详情") { viewingDeal = deal }.macSecondaryButton()
                            Button("编辑") { editingDeal = deal }.macSecondaryButton()
                            Button {
                                MacAlert.confirm("确定删除 \(deal.roomNumber) 这笔成交吗？", message: "删除后可在回收站还原。") {
                                    manager.softDeleteDeal(deal); MacToastCenter.show("已删除，可在回收站还原")
                                }
                            } label: { Image(systemName: "trash") }.macSecondaryButton()
                        }
                        .contextMenu {
                            Button("详情") { viewingDeal = deal }
                            Button("编辑") { editingDeal = deal }
                            Divider()
                            Button("删除", role: .destructive) {
                                MacAlert.confirm("确定删除 \(deal.roomNumber) 这笔成交吗？", message: "删除后可在回收站还原。") {
                                    manager.softDeleteDeal(deal)
                                    MacToastCenter.show("已删除，可在回收站还原")
                                }
                            }
                        }
                    }.width(170)
                }
                .contextMenu(forSelectionType: DealRecord.self) { items in
                    if let deal = items.first {
                        Button("详情") { viewingDeal = deal }
                        Button("编辑") { editingDeal = deal }
                        Divider()
                        Button("删除", role: .destructive) {
                            MacAlert.confirm("确定删除 \(deal.roomNumber) 这笔成交吗？", message: "删除后可在回收站还原。") {
                                manager.softDeleteDeal(deal)
                                MacToastCenter.show("已删除，可在回收站还原")
                            }
                        }
                    }
                }
            }
        }
    }

    /// 成交表格每行内容统一包右键菜单（macOS Table 行级右键不可靠，改为每个单元格 content 包裹，等效整行右键）
    @ViewBuilder
    private func dealCell<Content: View>(_ deal: DealRecord, @ViewBuilder content: () -> Content) -> some View {
        content()
            .contextMenu {
                Button("详情") { viewingDeal = deal }
                Button("编辑") { editingDeal = deal }
                Divider()
                Button("删除", role: .destructive) {
                    MacAlert.confirm("确定删除 \(deal.roomNumber) 这笔成交吗？", message: "删除后可在回收站还原。") {
                        manager.softDeleteDeal(deal)
                        MacToastCenter.show("已删除，可在回收站还原")
                    }
                }
            }
    }

    // MARK: 杂收杂支列表
    @ViewBuilder
    private func miscList(isIncome: Bool) -> some View {
        if isIncome {
            if incomes.isEmpty {
                emptyMiscList(isIncome: true)
            } else {
                incomeList
            }
        } else {
            if expenses.isEmpty {
                emptyMiscList(isIncome: false)
            } else {
                expenseList
            }
        }
    }

    private func emptyMiscList(isIncome: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: isIncome ? "arrow.down.circle" : "arrow.up.circle")
                .font(.system(size: 40, weight: .medium)).foregroundColor(.gray)
            Text(isIncome ? "暂无杂项收入" : "暂无杂项支出")
                .font(.system(size: 16, weight: .medium)).foregroundColor(.themeText3)
            Button(isIncome ? "新增收入" : "新增支出") {
                if isIncome { editingIncome = MiscIncome() } else { editingExpense = MiscExpense() }
            }.macSecondaryButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var incomeList: some View {
        List {
            ForEach(incomes) { row in
                miscRow(row: row, isIncome: true)
            }
        }
    }

    private var expenseList: some View {
        List {
            ForEach(expenses) { row in
                miscRow(row: row, isIncome: false)
            }
        }
    }

    @ViewBuilder
    private func miscRow(row: MiscIncome, isIncome: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.item).font(.system(size: 14, weight: .medium))
                if !row.notes.isEmpty { Text(row.notes).font(.system(size: 13, weight: .medium)).foregroundColor(.themeText3) }
                Text(FormatKit.dateStr(row.date)).font(.system(size: 11, weight: .medium)).foregroundColor(.themeText3)
            }
            Spacer()
            Text("+¥\(FormatKit.money(row.amount))")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.themeRed)
            Button("编辑") { editingIncome = row }.macSecondaryButton()
            Button {
                MacAlert.confirm("确定删除这条杂项收入吗？", message: "删除后可在回收站还原。") {
                    manager.softDeleteMiscIncome(row)
                    MacToastCenter.show("已删除，可在回收站还原")
                }
            } label: { Image(systemName: "trash") }.macSecondaryButton()
        }
        .padding(.vertical, 3)
        .background(highlightedID == row.id ? Color.yellow.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            highlightedID = row.id
            scheduleHighlightClear()
        }
        .contextMenu {
            Button("编辑") { editingIncome = row }
            Divider()
            Button("删除", role: .destructive) {
                MacAlert.confirm("确定删除这条杂项收入吗？", message: "删除后可在回收站还原。") {
                    manager.softDeleteMiscIncome(row)
                    MacToastCenter.show("已删除，可在回收站还原")
                }
            }
        }
    }

    @ViewBuilder
    private func miscRow(row: MiscExpense, isIncome: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.item).font(.system(size: 14, weight: .medium))
                if !row.notes.isEmpty { Text(row.notes).font(.system(size: 13, weight: .medium)).foregroundColor(.themeText3) }
                Text(FormatKit.dateStr(row.date)).font(.system(size: 11, weight: .medium)).foregroundColor(.themeText3)
            }
            Spacer()
            Text("-¥\(FormatKit.money(row.amount))")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.themeAccentDark)
            Button("编辑") { editingExpense = row }.macSecondaryButton()
            Button {
                MacAlert.confirm("确定删除这条杂项支出吗？", message: "删除后可在回收站还原。") {
                    manager.softDeleteMiscExpense(row)
                    MacToastCenter.show("已删除，可在回收站还原")
                }
            } label: { Image(systemName: "trash") }.macSecondaryButton()
        }
        .padding(.vertical, 3)
        .background(highlightedID == row.id ? Color.yellow.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            highlightedID = row.id
            scheduleHighlightClear()
        }
        .contextMenu {
            Button("编辑") { editingExpense = row }
            Divider()
            Button("删除", role: .destructive) {
                MacAlert.confirm("确定删除这条杂项支出吗？", message: "删除后可在回收站还原。") {
                    manager.softDeleteMiscExpense(row)
                    MacToastCenter.show("已删除，可在回收站还原")
                }
            }
        }
    }

    // MARK: 导出 / 导入
    private func scheduleHighlightClear() {
        highlightClearTask?.cancel()
        highlightClearTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { highlightedID = nil }
        }
    }

    /// 导出图片（对齐 iOS exportToImage：当前筛选结果渲染成 PNG）
    @MainActor
    private func exportToImage() {
        var title: String
        var headers: [String]
        var rows: [[String]]
        var highlight: Int? = nil
        if selectedTab == 0 {
            title = "成交记录"
            headers = ["日期", "房号", "房东", "户型", "租金", "中介费", "备注"]
            rows = deals.map { [
                FormatKit.dateStr($0.date), $0.roomNumber, $0.landlord, $0.unitType,
                "¥\(FormatKit.money($0.rent))", "¥\(FormatKit.money($0.totalFee))", $0.notes
            ] }
            if let sel = selection, let idx = deals.firstIndex(where: { $0.id == sel }) { highlight = idx }
        } else if selectedTab == 1 {
            title = "杂项收入"
            headers = ["日期", "项目", "金额", "备注"]
            rows = incomes.map { [FormatKit.dateStr($0.date), $0.item, "¥\(FormatKit.money($0.amount))", $0.notes] }
            if let sel = selection, let idx = incomes.firstIndex(where: { $0.id == sel }) { highlight = idx }
        } else {
            title = "杂项支出"
            headers = ["日期", "项目", "金额", "备注"]
            rows = expenses.map { [FormatKit.dateStr($0.date), $0.item, "¥\(FormatKit.money($0.amount))", $0.notes] }
            if let sel = selection, let idx = expenses.firstIndex(where: { $0.id == sel }) { highlight = idx }
        }
        ExportImageService.exportTable(title: title, headers: headers, rows: rows,
                                       filename: title, highlightRow: highlight)
    }

    /// 导出 Excel 模板（对齐 iOS exportTemplate：带示例行）
    private func exportTemplate() {
        var title: String
        var headers: [String]
        var sample: [[String]]
        if selectedTab == 0 {
            title = "成交记录"
            headers = ["成交日期", "房号", "房东", "户型", "起租期", "到期日", "租期", "月租金", "押金", "预存", "交租日", "房东中介费", "租客中介费", "管理人", "客源", "备注"]
            sample = [["2026-01-15", "1-101", "张三", "单间上层", "2026-01-15", "2027-01-14", "一年", "1000", "1000", "500", "1", "500", "500", "李四", "58同城", "示例数据"]]
        } else if selectedTab == 1 {
            title = "杂项收入"
            headers = ["日期", "项目", "金额", "备注"]
            sample = [["2026-01-15", "保洁费", "200", "示例"]]
        } else {
            title = "杂项支出"
            headers = ["日期", "项目", "金额", "备注"]
            sample = [["2026-01-15", "维修费", "300", "示例"]]
        }
        let data = ExcelService.makeExcelHTML(rows: [headers] + sample, sheetName: title)
        MacBridge.saveFile(defaultName: "\(title)-模板.xls", allowedTypes: [Self.xlsType, .spreadsheet]) { url in
            guard let url else { return }
            try? data.write(to: url)
            MacToastCenter.show("已导出模板（示例行请在导入前删除）")
        }
    }

    private func exportToExcel() {
        var rows: [[String]]
        var title: String
        if selectedTab == 0 {
            title = "成交记录"
            rows = [["成交日期", "房号", "房东", "户型", "租期开始", "租期结束", "租期描述", "月租金", "押金", "预存款", "交租日", "房东中介费", "客户中介费", "总中介费", "经办人", "来源", "备注"]]
            for deal in deals {
                rows.append([FormatKit.dateStr(deal.date), deal.roomNumber, deal.landlord, deal.unitType,
                             FormatKit.dateStr(deal.leaseStart), FormatKit.dateStr(deal.leaseEnd), deal.leaseDuration,
                             "\(FormatKit.money(deal.rent))", "\(FormatKit.money(deal.deposit))", "\(FormatKit.money(deal.prepayment))",
                             deal.rentDueDay.map(String.init) ?? "",
                             "\(FormatKit.money(deal.agentFeeLandlord))", "\(FormatKit.money(deal.agentFeeTenant))", "\(FormatKit.money(deal.totalFee))",
                             deal.manager, deal.source, deal.notes])
            }
        } else if selectedTab == 1 {
            title = "杂项收入"
            rows = [["日期", "项目", "金额", "备注"]]
            for inc in incomes { rows.append([FormatKit.dateStr(inc.date), inc.item, "\(FormatKit.money(inc.amount))", inc.notes]) }
        } else {
            title = "杂项支出"
            rows = [["日期", "项目", "金额", "备注"]]
            for exp in expenses { rows.append([FormatKit.dateStr(exp.date), exp.item, "\(FormatKit.money(exp.amount))", exp.notes]) }
        }
        let data = ExcelService.makeExcelHTML(rows: rows, sheetName: title)
        MacBridge.saveFile(defaultName: "\(title)_\(BackupTimestamp.string()).xls", allowedTypes: [Self.xlsType, .spreadsheet]) { url in
            guard let url = url else { return }
            try? data.write(to: url)
            MacToastCenter.show("已导出 \(rows.count - 1) 条记录")
        }
    }

    private func importFromFile() {
        MacBridge.openFiles(allowedTypes: [Self.xlsType, Self.csvType, .spreadsheet], allowsMultiple: false) { urls in
            guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
            let rows = ExcelService.parseImported(data)
            guard rows.count > 1 else { MacToastCenter.show("导入文件为空或格式不支持"); return }
            var added = 0
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
            if selectedTab == 0 {
                for row in rows.dropFirst() {
                    guard row.count >= 3 else { continue }
                    let date = df.date(from: row[0]) ?? Date()
                    manager.addDeal(date: date, roomNumber: row[1], landlord: row.count > 2 ? row[2] : "",
                                    unitType: row.count > 3 ? row[3] : "",
                                    leaseStart: df.date(from: row.count > 4 ? row[4] : "") ?? Date(),
                                    leaseEnd: df.date(from: row.count > 5 ? row[5] : "") ?? Date(),
                                    leaseDuration: row.count > 6 ? row[6] : "",
                                    rent: Double(row.count > 7 ? row[7].replacingOccurrences(of: ",", with: "") : "") ?? 0,
                                    deposit: Double(row.count > 8 ? row[8].replacingOccurrences(of: ",", with: "") : "") ?? 0,
                                    prepayment: Double(row.count > 9 ? row[9].replacingOccurrences(of: ",", with: "") : "") ?? 0,
                                    rentDueDay: Int(row.count > 10 ? row[10] : ""),
                                    agentFeeLandlord: Double(row.count > 11 ? row[11].replacingOccurrences(of: ",", with: "") : "") ?? 0,
                                    agentFeeTenant: Double(row.count > 12 ? row[12].replacingOccurrences(of: ",", with: "") : "") ?? 0,
                                    totalFee: Double(row.count > 13 ? row[13].replacingOccurrences(of: ",", with: "") : "") ?? 0,
                                    manager: row.count > 14 ? row[14] : "",
                                    source: row.count > 15 ? row[15] : "",
                                    notes: row.count > 16 ? row[16] : "")
                    added += 1
                }
            } else if selectedTab == 1 {
                for row in rows.dropFirst() where row.count >= 3 {
                    manager.addMiscIncome(date: df.date(from: row[0]) ?? Date(), item: row[1],
                                          amount: Double(row[2].replacingOccurrences(of: ",", with: "")) ?? 0,
                                          notes: row.count > 3 ? row[3] : "")
                    added += 1
                }
            } else {
                for row in rows.dropFirst() where row.count >= 3 {
                    manager.addMiscExpense(date: df.date(from: row[0]) ?? Date(), item: row[1],
                                           amount: Double(row[2].replacingOccurrences(of: ",", with: "")) ?? 0,
                                           notes: row.count > 3 ? row[3] : "")
                    added += 1
                }
            }
            MacToastCenter.show("已导入 \(added) 条记录")
        }
    }
}

// MARK: - 成交合同编辑器（对齐 iOS 契约字段）

struct DealEditor: View {
    @ObservedObject var manager: DataManager
    let deal: DealRecord?
    let onClose: () -> Void
    var onSaved: ((DealRecord) -> Void)? = nil

    @State private var date = Date()
    @State private var roomNumber = ""
    @State private var landlord = ""
    @State private var unitType = ""
    @State private var leaseStart = Date()
    @State private var leaseEnd = Date()
    @State private var leaseDuration = ""
    @State private var rent = ""
    @State private var deposit = ""
    @State private var prepayment = ""
    @State private var rentDueDay = "1"
    @State private var hasDueDay = false
    @State private var agentFeeLandlord = ""
    @State private var agentFeeTenant = ""
    @State private var totalFee = ""
    @State private var managerName = ""
    @State private var source = ""
    @State private var notes = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(deal == nil ? "新增成交" : "编辑成交").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19, weight: .medium)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        HStack(spacing: 10) {
                            DatePicker("成交日期", selection: $date, displayedComponents: .date).labelsHidden()
                            TextField("房号（如 2-1418）", text: $roomNumber)
                        }
                        HStack(spacing: 10) {
                            TextField("房东", text: $landlord)
                            TextField("户型（如 单间/复式）", text: $unitType)
                        }
                        HStack(spacing: 10) {
                            DatePicker("租期开始", selection: $leaseStart, displayedComponents: .date).labelsHidden()
                            DatePicker("租期结束", selection: $leaseEnd, displayedComponents: .date).labelsHidden()
                            TextField("租期描述（如 一年）", text: $leaseDuration)
                        }
                        HStack(spacing: 10) {
                            TextField("月租金", text: $rent)
                            TextField("押金", text: $deposit)
                            TextField("预存款", text: $prepayment)
                        }
                        HStack(spacing: 10) {
                            Toggle("交租日", isOn: $hasDueDay)
                            if hasDueDay {
                                TextField("1-31", text: $rentDueDay)
                                    .frame(width: 60)
                            }
                        }
                        HStack(spacing: 10) {
                            TextField("房东中介费", text: $agentFeeLandlord)
                            TextField("客户中介费", text: $agentFeeTenant)
                            TextField("总中介费", text: $totalFee)
                        }
                        HStack(spacing: 10) {
                            TextField("经办人", text: $managerName)
                            TextField("来源", text: $source)
                        }
                        TextField("备注", text: $notes)
                    }
                    .textFieldStyle(.roundedBorder)
                }
            }

            if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 14, weight: .medium)).foregroundColor(.themeDanger) }

            HStack {
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }.macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .onAppear {
            if let deal = deal {
                date = deal.date; roomNumber = deal.roomNumber; landlord = deal.landlord
                unitType = deal.unitType; leaseStart = deal.leaseStart; leaseEnd = deal.leaseEnd
                leaseDuration = deal.leaseDuration
                rent = "\(FormatKit.money(deal.rent))"; deposit = "\(FormatKit.money(deal.deposit))"
                prepayment = "\(FormatKit.money(deal.prepayment))"
                if let due = deal.rentDueDay { hasDueDay = true; rentDueDay = "\(due)" } else { hasDueDay = false }
                agentFeeLandlord = "\(FormatKit.money(deal.agentFeeLandlord))"
                agentFeeTenant = "\(FormatKit.money(deal.agentFeeTenant))"
                totalFee = "\(FormatKit.money(deal.totalFee))"
                managerName = deal.manager; source = deal.source; notes = deal.notes
            }
        }
    }

    private func save() {
        guard !roomNumber.isEmpty else { errorMessage = "请填写房号"; return }
        guard let r = Double(rent), r >= 0 else { errorMessage = "月租金无效"; return }
        let d = Double(deposit) ?? 0
        let p = Double(prepayment) ?? 0
        let due: Int? = hasDueDay ? (Int(rentDueDay).flatMap { (1...31).contains($0) ? $0 : nil }) : nil
        let aL = Double(agentFeeLandlord) ?? 0
        let aT = Double(agentFeeTenant) ?? 0
        let total = totalFee.isEmpty ? aL + aT : (Double(totalFee) ?? aL + aT)
        if let deal = deal {
            deal.date = date; deal.roomNumber = roomNumber; deal.landlord = landlord
            deal.unitType = unitType; deal.leaseStart = leaseStart; deal.leaseEnd = leaseEnd
            deal.leaseDuration = leaseDuration; deal.rent = r; deal.deposit = d; deal.prepayment = p
            deal.rentDueDay = due; deal.agentFeeLandlord = aL; deal.agentFeeTenant = aT
            deal.totalFee = total; deal.manager = managerName; deal.source = source; deal.notes = notes
            try? manager.mainContext.save()
            NotificationCenter.default.post(name: .macDataChanged, object: nil)
        } else {
            let record = manager.addDeal(date: date, roomNumber: roomNumber, landlord: landlord, unitType: unitType,
                                 leaseStart: leaseStart, leaseEnd: leaseEnd, leaseDuration: leaseDuration,
                                 rent: r, deposit: d, prepayment: p, rentDueDay: due,
                                 agentFeeLandlord: aL, agentFeeTenant: aT, totalFee: total,
                                 manager: managerName, source: source, notes: notes)
            onSaved?(record)
        }
        MacToastCenter.show("已保存")
        onClose()
    }
}

// MARK: - 成交合同详情

struct DealDetailView: View {
    @ObservedObject var manager: DataManager
    let deal: DealRecord
    let onClose: () -> Void

    private var rows: [(String, String)] {
        [
            ("成交日期", FormatKit.dateStr(deal.date)),
            ("房号", deal.roomNumber),
            ("房东", deal.landlord),
            ("户型", deal.unitType),
            ("租期", "\(FormatKit.dateStr(deal.leaseStart)) ~ \(FormatKit.dateStr(deal.leaseEnd))（\(deal.leaseDuration)）"),
            ("月租金", "¥\(FormatKit.money(deal.rent))"),
            ("押金", "¥\(FormatKit.money(deal.deposit))"),
            ("预存款", "¥\(FormatKit.money(deal.prepayment))"),
            ("交租日", deal.rentDueDay.map { "每月\($0)日" } ?? "未设置"),
            ("房东中介费", "¥\(FormatKit.money(deal.agentFeeLandlord))"),
            ("客户中介费", "¥\(FormatKit.money(deal.agentFeeTenant))"),
            ("总中介费", "¥\(FormatKit.money(deal.totalFee))"),
            ("经办人", deal.manager),
            ("来源", deal.source),
            ("备注", deal.notes),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("成交详情 · \(deal.roomNumber)").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19, weight: .medium)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows, id: \.0) { row in
                        HStack(alignment: .top) {
                            Text(row.0).font(.system(size: 14, weight: .medium)).foregroundColor(.themeText3).frame(width: 80, alignment: .leading)
                            Text(row.1).font(.system(size: 15, weight: .medium)).textSelection(.enabled)
                            Spacer()
                        }
                        Divider().opacity(0.4)
                    }
                }
            }
            HStack {
                Spacer()
                Button("编辑") { onClose() }
                    .macSecondaryButton()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 480, height: 520)
    }
}

// MARK: - 杂项收支编辑器

struct MiscEditor: View {
    @ObservedObject var manager: DataManager
    var income: MiscIncome?
    var expense: MiscExpense?
    let isIncome: Bool
    let onClose: () -> Void

    @State private var date = Date()
    @State private var item = ""
    @State private var amount = ""
    @State private var notes = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isIncome ? (income == nil ? "新增收入" : "编辑收入") : (expense == nil ? "新增支出" : "编辑支出"))
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19, weight: .medium)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }
            DatePicker(isIncome ? "收入日期" : "支出日期", selection: $date, displayedComponents: .date)
            TextField("项目", text: $item)
            TextField("金额", text: $amount)
            TextField("备注", text: $notes)
            if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 14, weight: .medium)).foregroundColor(.themeDanger) }
            HStack {
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }.macPrimaryButton()
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 380)
        .onAppear {
            if let income = income {
                date = income.date; item = income.item; amount = "\(FormatKit.money(income.amount))"; notes = income.notes
            }
            if let expense = expense {
                date = expense.date; item = expense.item; amount = "\(FormatKit.money(expense.amount))"; notes = expense.notes
            }
        }
    }

    private func save() {
        guard !item.isEmpty else { errorMessage = "请填写项目"; return }
        guard let a = Double(amount), a >= 0 else { errorMessage = "金额无效"; return }
        if let income = income {
            income.date = date; income.item = item; income.amount = a; income.notes = notes
            try? manager.mainContext.save()
            NotificationCenter.default.post(name: .macDataChanged, object: nil)
        } else if let expense = expense {
            expense.date = date; expense.item = item; expense.amount = a; expense.notes = notes
            try? manager.mainContext.save()
            NotificationCenter.default.post(name: .macDataChanged, object: nil)
        } else if isIncome {
            manager.addMiscIncome(date: date, item: item, amount: a, notes: notes)
        } else {
            manager.addMiscExpense(date: date, item: item, amount: a, notes: notes)
        }
        MacToastCenter.show("已保存")
        onClose()
    }
}
