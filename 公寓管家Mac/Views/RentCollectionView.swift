import SwiftUI
import SwiftData

// MARK: - 收租（已租房源收租计划 + 到期提醒）

struct RentCollectionView: View {
    @ObservedObject var manager: DataManager

    @State private var showPlanEditor = false
    @State private var selectedRentedHouse: House?

    private var houses: [House] { manager.houses }
    private var deals: [DealRecord] { manager.deals }

    /// 已租且未删除的房源
    private var rentedHouses: [House] {
        houses.filter { $0.isDeleted != true && $0.isRented }
            .sorted {
                if $0.tower != $1.tower { return $0.tower < $1.tower }
                return $0.displayRoomNo < $1.displayRoomNo
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("收租管理")
                    .font(.system(size: 19, weight: .bold))
                Text("已租 \(rentedHouses.count) 套")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText3)
                Spacer()
                Button {
                    showPlanEditor = true
                } label: {
                    Label("收租计划设置", systemImage: "calendar")
                }
                .macSecondaryButton()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if rentedHouses.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "banknote")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("暂无已租房源")
                        .font(.system(size: 14))
                        .foregroundColor(.themeText3)
                    Text("房源状态设为「已租」后会出现在这里")
                        .font(.system(size: 12))
                        .foregroundColor(.themeText3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(rentedHouses) { house in
                        RentRow(house: house, deals: deals) {
                            selectedRentedHouse = house
                        }
                    }
                }
            }
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showPlanEditor) {
            RentPlanEditor(manager: manager) { showPlanEditor = false }
        }
        .sheet(item: $selectedRentedHouse) { house in
            RentHouseDetail(manager: manager, house: house) { selectedRentedHouse = nil }
        }
    }
}

// MARK: - 收租行

struct RentRow: View {
    let house: House
    let deals: [DealRecord]
    let onTap: () -> Void

    private var lastDeal: DealRecord? {
        deals.filter { $0.roomNo == house.displayRoomNo }.sorted { $0.dealDate > $1.dealDate }.first
    }

    private var nextRentDate: Date? {
        guard let last = lastDeal else { return nil }
        return DataManager.nextRentDate(after: last.dealDate)
    }

    private var daysLeft: Int? {
        guard let next = nextRentDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: next).day
    }

    var body: some View {
        HStack(spacing: 12) {
            MediaThumbView(house: house, size: 42)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(house.displayRoomNo)
                        .font(.system(size: 14, weight: .semibold))
                    Text("房东 \(house.landlord)")
                        .font(.system(size: 11))
                        .foregroundColor(.themeText3)
                }
                Text("租金 ¥\(Int(house.price))/月")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText2)
            }
            Spacer()
            if let next = nextRentDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("下次收租：\(FormatKit.dateStr(next))")
                        .font(.system(size: 12))
                    if let days = daysLeft {
                        Text(days >= 0 ? "还有 \(days) 天" : "已逾期 \(-days) 天")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(days >= 0 ? .themeAccent : .themeDanger)
                    }
                }
            } else {
                Text("未设成交日期")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText3)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - 已租房源详情（收租记录 + 租期）

struct RentHouseDetail: View {
    @ObservedObject var manager: DataManager
    @Bindable var house: House
    let onClose: () -> Void

    @State private var rentRemark = ""
    @State private var leaseEnd: Date?

    private var houseDeals: [DealRecord] {
        manager.deals.filter { $0.roomNo == house.displayRoomNo }.sorted { $0.dealDate > $1.dealDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("收租详情 · \(house.displayRoomNo)")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }
                    .macSecondaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 租期
                    VStack(alignment: .leading, spacing: 8) {
                        Text("租期管理")
                            .font(.system(size: 14, weight: .semibold))
                        DatePicker("租期到期日", selection: Binding(
                            get: { leaseEnd ?? Date() },
                            set: { leaseEnd = $0 }
                        ), displayedComponents: .date)
                        HStack {
                            Button("保存租期") {
                                if let end = leaseEnd {
                                    LocalNotificationManager.schedule(
                                        title: "租期快到期",
                                        body: "\(house.displayRoomNo) 租期将于 \(FormatKit.dateStr(end)) 到期",
                                        at: end, id: LocalNotificationManager.expirePrefix + house.mediaRoomKey, tab: 4
                                    )
                                    MacToastCenter.show("已保存租期并设置到期提醒")
                                }
                            }
                            .macPrimaryButton()
                            Text("到期前会收到系统提醒")
                                .font(.system(size: 11))
                                .foregroundColor(.themeText3)
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    // 收租记录
                    VStack(alignment: .leading, spacing: 8) {
                        Text("收租记录")
                            .font(.system(size: 14, weight: .semibold))
                        if houseDeals.isEmpty {
                            Text("暂无收租记录，可到「成交」板块添加")
                                .font(.system(size: 12))
                                .foregroundColor(.themeText3)
                        } else {
                            ForEach(houseDeals) { deal in
                                HStack {
                                    Text(FormatKit.dateStr(deal.dealDate))
                                        .font(.system(size: 13))
                                    Text("¥\(FormatKit.money(deal.price))")
                                        .font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Text(deal.remark)
                                        .font(.system(size: 12))
                                        .foregroundColor(.themeText3)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.white)
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 560)
        .background(Color.themeBg)
        .onAppear {
            rentRemark = house.remark
        }
    }
}

// MARK: - 收租计划编辑器

struct RentPlanEditor: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var advanceDays = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("收租提醒设置")
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

            Toggle("启用本地提醒", isOn: Binding(
                get: { LocalNotificationManager.isEnabled },
                set: { v in
                    LocalNotificationManager.isEnabled = v
                    if !v { LocalNotificationManager.cancelAll() }
                }
            ))

            HStack {
                Text("提前提醒天数")
                Stepper(value: $advanceDays, in: 1...30) {
                    Text("\(advanceDays) 天")
                }
            }

            HStack {
                Spacer()
                Button("关闭") { onClose() }
                    .macSecondaryButton()
                Button("保存") {
                    LocalNotificationManager.advanceDays = advanceDays
                    MacToastCenter.show("提醒设置已保存")
                    onClose()
                }
                .macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { advanceDays = LocalNotificationManager.advanceDays }
    }
}
