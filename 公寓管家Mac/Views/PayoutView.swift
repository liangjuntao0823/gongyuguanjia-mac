import SwiftUI
import SwiftData

// MARK: - 包租（物业 + 支出流水）

struct PayoutView: View {
    @ObservedObject var manager: DataManager

    @State private var showAddProperty = false
    @State private var showAddPayout = false
    @State private var editingProperty: Property?
    @State private var editingPayout: PayoutRecord?

    private var properties: [Property] { manager.properties }
    private var payouts: [PayoutRecord] { manager.payouts }

    private var totalIncome: Double { properties.reduce(0) { $0 + $1.monthlyRent } }
    private var totalExpense: Double { properties.reduce(0) { $0 + $1.monthlyExpense } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("包租管理")
                    .font(.system(size: 19, weight: .bold))
                Text("物业 \(properties.count) 个 · 月收入 ¥\(FormatKit.money(totalIncome)) · 月支出 ¥\(FormatKit.money(totalExpense))")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText2)
                Spacer()
                Button {
                    showAddProperty = true
                } label: {
                    Label("新增物业", systemImage: "plus")
                }
                .macSecondaryButton()
                Button {
                    showAddPayout = true
                } label: {
                    Label("记一笔支出", systemImage: "minus.circle")
                }
                .macPrimaryButton()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            HStack(alignment: .top, spacing: 12) {
                // 左：物业
                VStack(alignment: .leading, spacing: 0) {
                    Text("物业")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    if properties.isEmpty {
                        VStack {
                            Text("暂无物业")
                                .font(.system(size: 13))
                                .foregroundColor(.themeText3)
                            Button("新增物业") { showAddProperty = true }
                                .macSecondaryButton()
                                .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(properties) { prop in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(prop.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Spacer()
                                        Button("编辑") { editingProperty = prop }
                                            .macSecondaryButton()
                                        Button("删除") { manager.deleteProperty(prop); MacToastCenter.show("已删除物业") }
                                            .macSecondaryButton()
                                    }
                                    Text("月租 ¥\(FormatKit.money(prop.monthlyRent)) · 月支出 ¥\(FormatKit.money(prop.monthlyExpense))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.themeText2)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color.themePanel)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
                .padding(.leading, 16)

                // 右：支出流水
                VStack(alignment: .leading, spacing: 0) {
                    Text("支出流水")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    if payouts.isEmpty {
                        VStack {
                            Text("暂无支出记录")
                                .font(.system(size: 13))
                                .foregroundColor(.themeText3)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(payouts.sorted { $0.date > $1.date }) { pay in
                                HStack {
                                    Text(FormatKit.dateStr(pay.date))
                                        .font(.system(size: 12))
                                        .frame(width: 80, alignment: .leading)
                                    Text(pay.category)
                                        .font(.system(size: 12))
                                        .frame(width: 70, alignment: .leading)
                                    Text("¥\(FormatKit.money(pay.amount))")
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Button("编辑") { editingPayout = pay }
                                        .macSecondaryButton()
                                    Button("删") { manager.deletePayout(pay); MacToastCenter.show("已删除") }
                                        .macSecondaryButton()
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color.themePanel)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
                .padding(.trailing, 16)
            }
            .padding(.vertical, 12)
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showAddProperty) {
            PropertyEditor(manager: manager, property: nil) { showAddProperty = false }
        }
        .sheet(item: $editingProperty) { prop in
            PropertyEditor(manager: manager, property: prop) { editingProperty = nil }
        }
        .sheet(isPresented: $showAddPayout) {
            PayoutEditor(manager: manager, payout: nil) { showAddPayout = false }
        }
        .sheet(item: $editingPayout) { pay in
            PayoutEditor(manager: manager, payout: pay) { editingPayout = nil }
        }
    }
}

// MARK: - 物业编辑器

struct PropertyEditor: View {
    @ObservedObject var manager: DataManager
    let property: Property?
    let onClose: () -> Void

    @State private var name = ""
    @State private var address = ""
    @State private var monthlyRent = ""
    @State private var monthlyExpense = ""
    @State private var remark = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(property == nil ? "新增物业" : "编辑物业")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            Group {
                TextField("物业名称", text: $name)
                TextField("地址", text: $address)
                TextField("月租金收入", text: $monthlyRent)
                TextField("月支出", text: $monthlyExpense)
                TextField("备注", text: $remark)
            }
            .textFieldStyle(.roundedBorder)

            if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 12)).foregroundColor(.themeDanger) }

            HStack {
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }.macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let property = property {
                name = property.name
                address = property.address
                monthlyRent = "\(FormatKit.money(property.monthlyRent))"
                monthlyExpense = "\(FormatKit.money(property.monthlyExpense))"
                remark = property.remark
            }
        }
    }

    private func save() {
        guard !name.isEmpty else { errorMessage = "请填写物业名称"; return }
        let rent = Double(monthlyRent) ?? 0
        let exp = Double(monthlyExpense) ?? 0
        if let property = property {
            manager.updateProperty(property, name: name, address: address, monthlyRent: rent, monthlyExpense: exp, remark: remark)
        } else {
            manager.addProperty(Property(name: name, address: address, monthlyRent: rent, monthlyExpense: exp, remark: remark))
        }
        MacToastCenter.show("已保存")
        onClose()
    }
}

// MARK: - 支出编辑器

struct PayoutEditor: View {
    @ObservedObject var manager: DataManager
    let payout: PayoutRecord?
    let onClose: () -> Void

    @State private var amount = ""
    @State private var category = "水电"
    @State private var date = Date()
    @State private var remark = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(payout == nil ? "记一笔支出" : "编辑支出")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            Group {
                TextField("金额", text: $amount)
                Picker("分类", selection: $category) {
                    Text("水电").tag("水电")
                    Text("维修").tag("维修")
                    Text("物业费").tag("物业费")
                    Text("中介费").tag("中介费")
                    Text("其他").tag("其他")
                }
                .pickerStyle(.segmented)
                DatePicker("日期", selection: $date, displayedComponents: .date)
                TextField("备注", text: $remark)
            }
            .textFieldStyle(.roundedBorder)

            if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 12)).foregroundColor(.themeDanger) }

            HStack {
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }.macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let payout = payout {
                amount = "\(FormatKit.money(payout.amount))"
                category = payout.category
                date = payout.date
                remark = payout.remark
            }
        }
    }

    private func save() {
        guard let a = Double(amount), a > 0 else { errorMessage = "金额无效"; return }
        if let payout = payout {
            manager.updatePayout(payout, amount: a, category: category, date: date, remark: remark)
        } else {
            manager.addPayout(PayoutRecord(amount: a, category: category, date: date, remark: remark))
        }
        MacToastCenter.show("已保存")
        onClose()
    }
}
