import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 成交记录（Table + 增删改 + Excel 导入导出）

struct DealsView: View {
    @ObservedObject var manager: DataManager

    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingDeal: DealRecord?

    private var deals: [DealRecord] { manager.deals }

    private var sorted: [DealRecord] {
        deals.sorted { $0.dealDate > $1.dealDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("成交记录")
                    .font(.system(size: 19, weight: .bold))
                Text("共 \(sorted.count) 条")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText3)
                Spacer()
                Button {
                    exportExcel()
                } label: {
                    Label("导出 Excel", systemImage: "square.and.arrow.up")
                }
                .macSecondaryButton()
                Button {
                    importExcel()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .macSecondaryButton()
                Button {
                    showAdd = true
                } label: {
                    Label("新增成交", systemImage: "plus")
                }
                .macPrimaryButton()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if sorted.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("暂无成交记录")
                        .font(.system(size: 14))
                        .foregroundColor(.themeText3)
                    Button("新增成交") { showAdd = true }
                        .macSecondaryButton()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sorted) {
                    TableColumn("日期") { deal in
                        Text(FormatKit.dateStr(deal.dealDate))
                    }
                    .width(100)
                    TableColumn("房号") { deal in
                        Text(deal.roomNo)
                    }
                    .width(90)
                    TableColumn("类型") { deal in
                        Text(deal.dealType)
                    }
                    .width(80)
                    TableColumn("金额") { deal in
                        Text("¥\(FormatKit.money(deal.price))")
                    }
                    .width(100)
                    TableColumn("佣金") { deal in
                        Text("¥\(FormatKit.money(deal.commission))")
                    }
                    .width(80)
                    TableColumn("杂费") { deal in
                        Text("¥\(FormatKit.money(deal.fee))")
                    }
                    .width(80)
                    TableColumn("付款方") { deal in
                        Text(deal.paidBy)
                    }
                    .width(80)
                    TableColumn("备注") { deal in
                        Text(deal.remark)
                            .lineLimit(1)
                    }
                    TableColumn("操作") { deal in
                        HStack(spacing: 8) {
                            Button("编辑") { editingDeal = deal }
                                .macSecondaryButton()
                            Button("删除") { delete(deal) }
                                .macSecondaryButton()
                        }
                    }
                    .width(120)
                }
            }
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showAdd) {
            DealEditor(manager: manager, deal: nil) { showAdd = false }
        }
        .sheet(item: $editingDeal) { deal in
            DealEditor(manager: manager, deal: deal) { editingDeal = nil }
        }
    }

    private func delete(_ deal: DealRecord) {
        manager.deleteDeal(deal)
        MacToastCenter.show("已删除成交记录")
    }

    private func exportExcel() {
        var rows: [[String]] = [["日期", "房号", "类型", "金额", "佣金", "杂费", "付款方", "备注"]]
        for deal in sorted {
            rows.append([
                FormatKit.dateStr(deal.dealDate), deal.roomNo, deal.dealType,
                "\(FormatKit.money(deal.price))", "\(FormatKit.money(deal.commission))",
                "\(FormatKit.money(deal.fee))", deal.paidBy, deal.remark
            ])
        }
        let data = ExcelService.makeExcelHTML(rows: rows, sheetName: "成交记录")
        MacBridge.saveFile(defaultName: "成交记录_\(BackupTimestamp.string()).xls", allowedTypes: [.xls, .spreadsheet]) { url in
            guard let url = url else { return }
            try? data.write(to: url)
            MacToastCenter.show("已导出 \(sorted.count) 条成交记录")
        }
    }

    private func importExcel() {
        MacBridge.openFiles(allowedTypes: [.xls, .csv, .spreadsheet], allowsMultiple: false) { urls in
            guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
            let rows = ExcelService.parseImported(data)
            guard rows.count > 1 else {
                MacToastCenter.show("导入文件为空或格式不支持")
                return
            }
            var added = 0
            for row in rows.dropFirst() {
                guard row.count >= 3 else { continue }
                let dateStr = row[0]
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                df.locale = Locale(identifier: "en_US_POSIX")
                let date = df.date(from: dateStr) ?? Date()
                let roomNo = row[1]
                let type = row.count > 2 ? row[2] : "成交"
                let price = Double(row.count > 3 ? row[3].replacingOccurrences(of: ",", with: "") : "") ?? 0
                let commission = Double(row.count > 4 ? row[4].replacingOccurrences(of: ",", with: "") : "") ?? 0
                let fee = Double(row.count > 5 ? row[5].replacingOccurrences(of: ",", with: "") : "") ?? 0
                let paidBy = row.count > 6 ? row[6] : ""
                let remark = row.count > 7 ? row[7] : ""
                manager.addDeal(DealRecord(roomNo: roomNo, dealDate: date, dealType: type, price: price,
                                           commission: commission, fee: fee, paidBy: paidBy, remark: remark))
                added += 1
            }
            MacToastCenter.show("已导入 \(added) 条成交记录")
        }
    }
}

// MARK: - 成交编辑器

struct DealEditor: View {
    @ObservedObject var manager: DataManager
    let deal: DealRecord?
    let onClose: () -> Void

    @State private var roomNo = ""
    @State private var dealDate = Date()
    @State private var dealType = "成交"
    @State private var price = ""
    @State private var commission = ""
    @State private var fee = ""
    @State private var paidBy = ""
    @State private var remark = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(deal == nil ? "新增成交" : "编辑成交")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Group {
                TextField("房号", text: $roomNo)
                DatePicker("成交日期", selection: $dealDate, displayedComponents: .date)
                Picker("类型", selection: $dealType) {
                    Text("成交").tag("成交")
                    Text("中介费").tag("中介费")
                    Text("续租").tag("续租")
                    Text("其他").tag("其他")
                }
                .pickerStyle(.segmented)
                HStack(spacing: 10) {
                    TextField("金额", text: $price)
                    TextField("佣金", text: $commission)
                }
                HStack(spacing: 10) {
                    TextField("杂费/其他", text: $fee)
                    TextField("付款方", text: $paidBy)
                }
                TextField("备注", text: $remark)
            }
            .textFieldStyle(.roundedBorder)

            if !errorMessage.isEmpty {
                Text(errorMessage).font(.system(size: 12)).foregroundColor(.themeDanger)
            }

            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .macSecondaryButton()
                Button("保存") { save() }
                    .macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if let deal = deal {
                roomNo = deal.roomNo
                dealDate = deal.dealDate
                dealType = deal.dealType
                price = "\(FormatKit.money(deal.price))"
                commission = "\(FormatKit.money(deal.commission))"
                fee = "\(FormatKit.money(deal.fee))"
                paidBy = deal.paidBy
                remark = deal.remark
            }
        }
    }

    private func save() {
        guard !roomNo.isEmpty else { errorMessage = "请填写房号"; return }
        guard let p = Double(price), p >= 0 else { errorMessage = "金额无效"; return }
        let c = Double(commission) ?? 0
        let f = Double(fee) ?? 0
        if let deal = deal {
            manager.updateDeal(deal, roomNo: roomNo, dealDate: dealDate, dealType: dealType,
                               price: p, commission: c, fee: f, paidBy: paidBy, remark: remark)
        } else {
            manager.addDeal(DealRecord(roomNo: roomNo, dealDate: dealDate, dealType: dealType,
                                       price: p, commission: c, fee: f, paidBy: paidBy, remark: remark))
        }
        MacToastCenter.show("已保存")
        onClose()
    }
}
