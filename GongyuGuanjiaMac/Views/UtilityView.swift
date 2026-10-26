import SwiftUI
import SwiftData

// MARK: - 水电结算工具（对齐 iOS：结算单生成 + 写入计划周期 + 历史管理）

struct UtilityView: View {
    @ObservedObject var manager: DataManager
    var presetProperty: Property? = nil
    var onWriteSuccess: (() -> Void)? = nil
    var onClose: () -> Void = {}

    @State private var selectedProperty: Property?
    @State private var includesMaster = false
    @State private var electricPriceText = "0.8"
    @State private var waterPriceText = "5.5"
    @State private var electricTotalText = ""
    @State private var electricSubText = ""
    @State private var electricBaseText = ""
    @State private var waterTotalText = ""
    @State private var waterSubText = ""
    @State private var waterBaseText = ""
    @State private var prepaymentText = ""
    @State private var showHistory = false
    @State private var copied = false
    @State private var pendingHistory: UtilitySettlementHistory?
    @State private var showPeriodChoice = false
    @State private var showSaved = false
    @AppStorage("defaultElectricPrice") private var defaultElectricPrice = "0.8"
    @AppStorage("defaultWaterPrice") private var defaultWaterPrice = "5.5"
    @AppStorage("defaultUtilityPrepayment") private var defaultUtilityPrepayment = "0"

    private var properties: [Property] { manager.properties.filter { $0.isDeleted != true && !$0.isTerminated } }

    private var room: String { selectedProperty?.roomNumber ?? "" }
    private var ePrice: Double { Double(electricPriceText) ?? 0.8 }
    private var wPrice: Double { Double(waterPriceText) ?? 5.5 }
    private var eTotal: Double { Double(electricTotalText) ?? 0 }
    private var eSub: Double { Double(electricSubText) ?? 0 }
    private var eBase: Double { Double(electricBaseText) ?? 0 }
    private var wTotal: Double { Double(waterTotalText) ?? 0 }
    private var wSub: Double { Double(waterSubText) ?? 0 }
    private var wBase: Double { Double(waterBaseText) ?? 0 }
    private var prepay: Double { Double(prepaymentText) ?? 0 }
    private var eLatest: Double { includesMaster ? eTotal - eSub : eSub }
    private var wLatest: Double { includesMaster ? wTotal - wSub : wSub }
    private var eUsage: Double { eLatest - eBase }
    private var wUsage: Double { wLatest - wBase }
    private var hasElectric: Bool { !electricSubText.isEmpty || (includesMaster && !electricTotalText.isEmpty) }
    private var hasWater: Bool { !waterSubText.isEmpty || (includesMaster && !waterTotalText.isEmpty) }
    private var eCost: Int { hasElectric ? Int((eUsage * ePrice).rounded()) : 0 }
    private var wCost: Int { hasWater ? Int((wUsage * wPrice).rounded()) : 0 }
    private var balance: Int { Int(prepay.rounded()) - eCost - wCost }
    private func n(_ v: Double) -> String { String(format: v.rounded() == v ? "%.0f" : "%.2f", v) }
    private var statement: String {
        let f = DateFormatter(); f.dateFormat = "yyyy年M月d日"
        var lines = ["\(room.isEmpty ? "XXX" : room)房截止\(f.string(from: Date()))"]
        if includesMaster {
            if hasElectric { lines.append("用电：\(n(eTotal))-\(n(eSub))=\(n(eLatest))-\(n(eBase))=\(n(eUsage))x\(n(ePrice))=\(eCost)元") } else { lines.append("用电：暂不结算") }
            if hasWater { lines.append("用水：\(n(wTotal))-\(n(wSub))=\(n(wLatest))-\(n(wBase))=\(n(wUsage))x\(n(wPrice))=\(wCost)元") } else { lines.append("用水：暂不结算") }
        } else {
            if hasElectric { lines.append("用电：\(n(eSub))-\(n(eBase))=\(n(eUsage))x\(n(ePrice))=\(eCost)元") } else { lines.append("用电：暂不结算") }
            if hasWater { lines.append("用水：\(n(wSub))-\(n(wBase))=\(n(wUsage))x\(n(wPrice))=\(wCost)元") } else { lines.append("用水：暂不结算") }
        }
        lines.append("预存结算：\(Int(prepay.rounded()))-\(eCost)-\(wCost)=\(balance)元")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("水电结算").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("计算历史") { showHistory = true }.macSecondaryButton()
                Button("关闭") { onClose() }.macSecondaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("房源信息") {
                        Picker("房号", selection: $selectedProperty) {
                            Text("请选择").tag(nil as Property?)
                            ForEach(properties) { prop in
                                Text(prop.roomNumber).tag(prop as Property?)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("是否带总表计算", selection: $includesMaster) {
                            Text("不带总表").tag(false)
                            Text("带总表").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    section("单价设置") {
                        amountRow("电费单价", $electricPriceText, unit: "元/度")
                        amountRow("水费单价", $waterPriceText, unit: "元/吨")
                    }
                    section("电费计算") {
                        if includesMaster { amountRow("总表读数", $electricTotalText) }
                        amountRow("分表读数", $electricSubText)
                        amountRow("登记底数", $electricBaseText)
                        infoRow("用电量", "\(n(eUsage))度")
                        infoRow("电费", "\(eCost)元")
                    }
                    section("水费计算") {
                        if includesMaster { amountRow("总表读数", $waterTotalText) }
                        amountRow("分表读数", $waterSubText)
                        amountRow("登记底数", $waterBaseText)
                        infoRow("用水量", "\(n(wUsage))吨")
                        infoRow("水费", "\(wCost)元")
                    }
                    section("预存结算") {
                        amountRow("总预存", $prepaymentText)
                        infoRow("结余", "\(balance)元")
                    }
                    section("结算单") {
                        Text(statement)
                            .font(.system(size: 16))
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                        HStack(spacing: 10) {
                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(statement, forType: .string)
                                copied = true
                                MacToastCenter.show("已复制结算单")
                            } label: { Label(copied ? "已复制" : "一键复制", systemImage: "doc.on.doc") }
                            .macSecondaryButton()
                            Button("保存并写入周期") { save() }
                                .macPrimaryButton()
                                .disabled(selectedProperty == nil || (!hasElectric && !hasWater))
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 660)
        .background(Color.themeBg)
        .sheet(isPresented: $showHistory) { UtilityHistoryView(manager: manager) }
        .sheet(isPresented: $showPeriodChoice) {
            if let p = selectedProperty, let h = pendingHistory {
                UtilityPeriodChoiceView(manager: manager, property: p, history: h) {
                    showPeriodChoice = false
                    showSaved = true
                }
            }
        }
        .alert("写入成功", isPresented: $showSaved) {
            Button("确定", role: .cancel) { onWriteSuccess?(); onClose() }
        } message: {
            Text("水电金额、结余和结算单已写入所选周期。")
        }
        .onAppear {
            electricPriceText = defaultElectricPrice
            waterPriceText = defaultWaterPrice
            prepaymentText = defaultUtilityPrepayment
            if let p = presetProperty {
                selectedProperty = p
                electricBaseText = String(p.electricMeterBase)
                waterBaseText = String(p.waterMeterBase)
            }
        }
        .onChange(of: selectedProperty) { _, p in
            if let p {
                electricBaseText = String(p.electricMeterBase)
                waterBaseText = String(p.waterMeterBase)
            }
        }
    }

    private func amountRow(_ title: String, _ text: Binding<String>, unit: String = "") -> some View {
        HStack {
            Text(title).font(.system(size: 15))
            Spacer()
            TextField("请输入", text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
            if !unit.isEmpty { Text(unit).font(.system(size: 14)).foregroundColor(.themeText3) }
        }
    }
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15))
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold))
        }
    }
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.themeText2)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorder))
    }

    private func save() {
        guard let p = selectedProperty else { return }
        if hasElectric { p.electricMeterBase = Int(eLatest.rounded()) }
        if hasWater { p.waterMeterBase = Int(wLatest.rounded()) }
        let maxOrder = manager.utilityHistories.map(\.sortOrder).max() ?? -1
        let h = UtilitySettlementHistory(roomNumber: p.roomNumber, statement: statement, settledAt: Date(),
                                         includesMaster: includesMaster, electricLatest: eLatest, waterLatest: wLatest,
                                         electricCost: Double(eCost), waterCost: Double(wCost),
                                         balance: Double(balance), sortOrder: maxOrder + 1)
        manager.mainContext.insert(h)
        try? manager.mainContext.save()
        pendingHistory = h
        showPeriodChoice = true
    }
}

// MARK: - 计算历史

struct UtilityHistoryView: View {
    @ObservedObject var manager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selected: UtilitySettlementHistory?
    @State private var editing: UtilitySettlementHistory?
    @State private var deleting: UtilitySettlementHistory?

    private var histories: [UtilitySettlementHistory] {
        manager.utilityHistories.sorted { $0.settledAt > $1.settledAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("计算历史").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("关闭") { dismiss() }.macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.themeText3)
                TextField("搜索房号或结算内容", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
            }
            .padding(10)
            List {
                ForEach(histories.filter {
                    searchText.isEmpty ||
                    $0.roomNumber.localizedCaseInsensitiveContains(searchText) ||
                    $0.statement.localizedCaseInsensitiveContains(searchText)
                }) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.roomNumber + "房").font(.system(size: 15, weight: .semibold))
                        Text(item.settledAt.formatted(date: .numeric, time: .shortened)).font(.system(size: 13)).foregroundColor(.themeText3)
                        Text(item.statement).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = item }
                    .contextMenu {
                        Button {
                            let f = DateFormatter(); f.dateFormat = "yyyy年M月d日 HH:mm"
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString("\(item.roomNumber)房 \(f.string(from: item.settledAt))\n\(item.statement)", forType: .string)
                            MacToastCenter.show("已复制")
                        } label: { Label("复制", systemImage: "doc.on.doc") }
                        Button { editing = item } label: { Label("编辑", systemImage: "pencil") }
                        Button(role: .destructive) { deleting = item } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
        }
        .frame(width: 560, height: 520)
        .sheet(item: $selected) { UtilityHistoryPreview(history: $0) }
        .sheet(item: $editing) { UtilityHistoryEditView(manager: manager, history: $0) }
        .confirmationDialog("确认删除这条结算记录？删除后无法恢复。",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("确定删除", role: .destructive) {
                if let d = deleting {
                    manager.mainContext.delete(d)
                    try? manager.mainContext.save()
                    NotificationCenter.default.post(name: .macDataChanged, object: nil)
                    MacToastCenter.show("已删除")
                }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }
}

struct UtilityHistoryEditView: View {
    @ObservedObject var manager: DataManager
    @Environment(\.dismiss) private var dismiss
    let history: UtilitySettlementHistory
    @State private var text: String

    init(manager: DataManager, history: UtilitySettlementHistory) {
        self.manager = manager
        self.history = history
        _text = State(initialValue: history.statement)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑结算单").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("取消") { dismiss() }.macSecondaryButton()
                Button("保存") {
                    history.statement = text
                    try? manager.mainContext.save()
                    NotificationCenter.default.post(name: .macDataChanged, object: nil)
                    MacToastCenter.show("已保存")
                    dismiss()
                }.macPrimaryButton()
            }
            .padding(14)
            Divider()
            TextEditor(text: $text)
                .font(.system(size: 15))
                .padding(10)
        }
        .frame(width: 520, height: 380)
    }
}

struct UtilityHistoryPreview: View {
    @Environment(\.dismiss) private var dismiss
    let history: UtilitySettlementHistory

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(history.roomNumber + "房结算单").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("关闭") { dismiss() }.macPrimaryButton()
            }
            .padding(14)
            Divider()
            ScrollView {
                UtilityStatementCard(history: history).padding()
            }
        }
        .frame(width: 460, height: 560)
    }
}

struct UtilityStatementCard: View {
    let history: UtilitySettlementHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(history.roomNumber + "房水电结算单").font(.system(size: 23, weight: .bold))
            Text(history.settledAt.formatted(date: .long, time: .omitted)).foregroundColor(.secondary)
            Divider()
            Text(history.statement).font(.system(size: 17)).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("电费 \(Int(history.electricCost))元")
                Spacer()
                Text("水费 \(Int(history.waterCost))元")
            }
            Text("预存结余 \(Int(history.balance))元").font(.headline)
        }
        .padding(20)
        .background(Color.white)
        .foregroundColor(.black)
        .cornerRadius(14)
    }
}

// MARK: - 写入结算周期

struct UtilityPeriodChoiceView: View {
    @ObservedObject var manager: DataManager
    @Environment(\.dismiss) private var dismiss
    let property: Property
    let history: UtilitySettlementHistory
    let onDone: () -> Void

    private var uniqueRecords: [UtilitySettlementRecord] {
        var seen = Set<String>()
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        return property.utilitySettlementRecords
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .filter { seen.insert(f.string(from: $0.dueDate ?? .distantFuture)).inserted }
    }
    private func periodTitle(_ record: UtilitySettlementRecord) -> String {
        if let date = record.dueDate {
            let f = DateFormatter(); f.dateFormat = "yyyy年M月d日"
            return f.string(from: date)
        }
        return "\(record.year)年\(record.period)月"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("写入结算周期").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("取消") { dismiss() }.macSecondaryButton()
            }
            .padding(14)
            Divider()
            List {
                ForEach(uniqueRecords) { record in
                    Button {
                        record.electricAmount = Double(history.electricCost)
                        record.waterAmount = Double(history.waterCost)
                        record.balance = Double(history.balance)
                        record.isSettled = true
                        record.statement = history.statement
                        record.settledAt = history.settledAt
                        if let d = record.dueDate {
                            let cal = Calendar.current
                            if let rent = property.monthlyRentRecords.first(where: {
                                $0.year == cal.component(.year, from: d) && $0.month == cal.component(.month, from: d)
                            }) {
                                rent.amount = property.rent + property.prepayment - record.balance
                            }
                        }
                        try? manager.mainContext.save()
                        NotificationCenter.default.post(name: .macDataChanged, object: nil)
                        dismiss()
                        onDone()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(periodTitle(record)).font(.system(size: 15, weight: .semibold))
                            HStack {
                                Text(record.isSettled ? "已结算" : "未结算")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text("电\(Int(record.electricAmount)) 水\(Int(record.waterAmount)) 余\(Int(record.balance))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 460, height: 420)
    }
}

// MARK: - sheet 关闭辅助通知

extension Notification.Name {
    static let macSheetDismiss = Notification.Name("macSheetDismiss")
}
