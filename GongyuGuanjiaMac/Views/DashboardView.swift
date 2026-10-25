import SwiftUI
import SwiftData

// MARK: - 工作台（对齐 iOS：KPI 统计 + 收租/包租/到期提醒 + 待办 + 快捷操作）

struct DashboardView: View {
    @ObservedObject var manager: DataManager

    @State private var showTodo = false
    @State private var showUtility = false

    private var stats: DashboardStats { manager.dashboardStats() }
    private var activeProperties: [Property] {
        manager.properties.filter { $0.isDeleted != true && !$0.isTerminated }
    }
    private var payouts: [PayoutRecord] { manager.payouts.filter { $0.isDeleted != true } }

    private var dueTodayRent: [Property] {
        let day = Calendar.current.component(.day, from: Date())
        return activeProperties.filter {
            $0.rentDueDay == day &&
            !($0.monthlyRentRecords.contains { $0.isPaid && Calendar.current.component(.month, from: Date()) == $0.month })
        }
    }
    private var overdueRent: [Property] {
        let day = Calendar.current.component(.day, from: Date())
        return activeProperties.filter { $0.rentDueDay < day && !$0.isPaidForCard }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("公寓管家 · 工作台")
                            .font(.system(size: 22, weight: .bold))
                        Text(FormatKit.dateStr(Date()))
                            .font(.system(size: 13))
                            .foregroundColor(.themeText2)
                    }
                    Spacer()
                    Button {
                        if let config = CosConfig.load() {
                            MacBridge.openURL(CosConfig.statsURL(config: config))
                        } else {
                            MacToastCenter.show("未配置云端，请先在设置中完成云端配置")
                        }
                    } label: {
                        Label("云端统计后台", systemImage: "chart.bar.fill")
                    }
                    .macPrimaryButton()
                }
                .padding(.top, 4)

                // KPI 卡片
                HStack(spacing: 12) {
                    StatCard(title: "在租房源", value: "\(stats.totalProperties)", icon: "house.fill", color: .themeAccent) { manager.selectedTab = .rents }
                    StatCard(title: "管理房源", value: "\(stats.activeProperties)", icon: "checkmark.seal.fill", color: .themeBlue) { manager.selectedTab = .rents }
                    StatCard(title: "本月应收", value: "¥\(Int(stats.monthlyRentReceivable))", icon: "banknote.fill", color: .themeWarning) { manager.selectedTab = .rents }
                    StatCard(title: "本月实收", value: "¥\(Int(stats.monthlyRentCollected))", icon: "checkmark.circle.fill", color: .themeAccentDark) { manager.selectedTab = .rents }
                    StatCard(title: "本月中介费", value: "¥\(Int(stats.monthlyDealFee))", icon: "doc.text.fill", color: .themeDanger) { manager.selectedTab = .deals }
                    StatCard(title: "包租盈亏", value: "¥\(Int(stats.packageProfit))", icon: "chart.line.uptrend.xyaxis", color: stats.packageProfit >= 0 ? .themeAccentDark : .themeRed) { manager.selectedTab = .payouts }
                }

                // 提醒区
                VStack(alignment: .leading, spacing: 8) {
                    Text("提醒")
                        .font(.system(size: 15, weight: .semibold))
                    let reminders = buildReminders()
                    if reminders.isEmpty {
                        Text("暂无待处理事项")
                            .font(.system(size: 13))
                            .foregroundColor(.themeText3)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(reminders) { item in
                            Button {
                                item.action()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.icon)
                                        .foregroundColor(item.color)
                                        .frame(width: 18)
                                    Text(item.text)
                                        .font(.system(size: 13))
                                        .foregroundColor(.themeText)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(.themeText3)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .background(Color.themePanel)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                // 快捷操作
                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷操作")
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 12) {
                        QuickAction(icon: "banknote.fill", title: "快捷收租") { manager.selectedTab = .rents }
                        QuickAction(icon: "briefcase.fill", title: "快捷付租") { manager.selectedTab = .payouts }
                        QuickAction(icon: "plus.circle.fill", title: "新增房源") { manager.selectedTab = .houses }
                        QuickAction(icon: "checklist", title: "待办事项") { showTodo = true }
                        QuickAction(icon: "bolt.fill", title: "水电结算") { showUtility = true }
                        QuickAction(icon: "externaldrive.fill", title: "备份中心") { manager.selectedTab = .settings }
                    }
                }
                .padding(14)
                .background(Color.themePanel)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                Spacer(minLength: 20)
            }
            .padding(18)
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showTodo) { TodoViews(manager: manager) { showTodo = false } }
        .sheet(isPresented: $showUtility) { UtilityView(manager: manager) { showUtility = false } }
    }

    private struct ReminderItem: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let color: Color
        let action: () -> Void
    }

    private func buildReminders() -> [ReminderItem] {
        var out: [ReminderItem] = []
        // 今天交租
        if !dueTodayRent.isEmpty {
            out.append(ReminderItem(icon: "calendar.badge.exclamationmark", text: "今天应收租：\(dueTodayRent.map(\.roomNumber).joined(separator: "、"))",
                                    color: .themeWarning) { manager.selectedTab = .rents })
        }
        // 逾期
        if !overdueRent.isEmpty {
            out.append(ReminderItem(icon: "exclamationmark.triangle.fill", text: "逾期未收：\(overdueRent.map(\.roomNumber).joined(separator: "、"))",
                                    color: .themeRed) { manager.selectedTab = .rents })
        }
        // 30 天到期
        if !stats.expiringSoon.isEmpty {
            out.append(ReminderItem(icon: "clock.fill", text: "30天内到期：\(stats.expiringSoon.map(\.roomNumber).joined(separator: "、"))",
                                    color: .themeAccent) { manager.selectedTab = .rents })
        }
        // 包租下一期
        let overduePayouts = payouts.filter { payout in
            let now = Date()
            let cal = Calendar.current
            let dueDay = payout.rentDueDay
            let comps = cal.dateComponents([.year, .month], from: now)
            var dueComps = DateComponents()
            dueComps.year = comps.year
            dueComps.month = comps.month
            dueComps.day = dueDay
            guard let due = cal.date(from: dueComps) else { return false }
            let diff = cal.dateComponents([.day], from: due, to: now).day ?? 0
            return diff > 0 && !payout.monthlyPayouts.contains { $0.isPaid }
        }
        if !overduePayouts.isEmpty {
            out.append(ReminderItem(icon: "briefcase.fill", text: "包租待付：\(overduePayouts.map(\.roomNumber).joined(separator: "、"))",
                                    color: .themeDanger) { manager.selectedTab = .payouts })
        }
        // 待办未完成
        let pendingTodos = manager.todos.filter { $0.isDeleted != true && !$0.isCompleted }
        if !pendingTodos.isEmpty {
            out.append(ReminderItem(icon: "checklist", text: "待办事项 \(pendingTodos.count) 条未完成",
                                    color: .themeBlue) { showTodo = true })
        }
        return out
    }
}

// MARK: - 指标卡

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(color)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.themeText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.themeText2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.themePanel)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 快捷操作

struct QuickAction: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.themeAccent)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.themeText)
            }
            .frame(width: 96, height: 72)
            .background(Color.white)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorder))
        }
        .buttonStyle(.plain)
    }
}
