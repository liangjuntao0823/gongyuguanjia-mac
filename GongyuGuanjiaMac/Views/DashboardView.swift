import SwiftUI
import SwiftData

// MARK: - 工作台（dashboard）：核心指标 + 快捷入口 + 待办提醒

struct DashboardView: View {
    @ObservedObject var manager: DataManager
    @Environment(\.houseModelContext) private var houseEnvContext

    private var houses: [House] { manager.houses }
    private var deals: [DealRecord] { manager.deals }
    private var payouts: [PayoutRecord] { manager.payouts }

    private var stats: DataManager.HouseStats {
        manager.houseStats(houses)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 顶部问候
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("早上好，\(CloudUser.displayName)")
                            .font(.system(size: 22, weight: .bold))
                        Text(FormatKit.dateStr(Date()))
                            .font(.system(size: 13))
                            .foregroundColor(.themeText2)
                    }
                    Spacer()
                    Button {
                        manager.selectedTab = .houses
                    } label: {
                        Label("管理房源", systemImage: "house")
                    }
                    .macPrimaryButton()
                }
                .padding(.top, 4)

                // 指标卡
                HStack(spacing: 12) {
                    StatCard(title: "总房源", value: "\(stats.total)", icon: "house.fill", color: .themeAccent) {
                        manager.selectedTab = .houses
                    }
                    StatCard(title: "待租", value: "\(stats.available)", icon: "checkmark.circle.fill", color: .themeBlue) {
                        manager.selectedTab = .houses
                    }
                    StatCard(title: "已租", value: "\(stats.rented)", icon: "lock.fill", color: .themeWarning) {
                        manager.selectedTab = .houses
                    }
                    StatCard(title: "本月成交", value: "\(deals.count)", icon: "doc.text.fill", color: .themeDanger) {
                        manager.selectedTab = .deals
                    }
                    StatCard(title: "待收租记录", value: "\(payouts.count)", icon: "banknote.fill", color: .purple) {
                        manager.selectedTab = .rents
                    }
                }

                // 待处理提醒
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
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .foregroundColor(item.color)
                                    .frame(width: 18)
                                Text(item.text)
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(Color.white)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(14)
                .background(Color.themePanel)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                // 快速入口
                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷操作")
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 12) {
                        QuickAction(icon: "plus.circle.fill", title: "新增房源") { manager.selectedTab = .houses }
                        QuickAction(icon: "arrow.triangle.2.circlepath", title: "云端同步") { manager.selectedTab = .settings }
                        QuickAction(icon: "externaldrive.fill", title: "备份中心") { manager.selectedTab = .settings }
                        QuickAction(icon: "square.and.arrow.up.fill", title: "生成选房链接") { manager.selectedTab = .settings }
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
    }

    private struct ReminderItem: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let color: Color
    }

    private func buildReminders() -> [ReminderItem] {
        var out: [ReminderItem] = []
        // 待租房源无实拍图
        let noPhoto = houses.filter { $0.isDeleted != true && $0.isAvailable && !$0.hasRealPhoto }
        if !noPhoto.isEmpty {
            out.append(ReminderItem(icon: "camera.fill", text: "\(noPhoto.count) 套待租房源还没有实拍图", color: .themeWarning))
        }
        // 已租房源提醒（租金已收/待收占位：简单提示待办）
        let rented = houses.filter { $0.isDeleted != true && $0.isRented }
        if !rented.isEmpty {
            out.append(ReminderItem(icon: "lock.fill", text: "\(rented.count) 套已租房源在租", color: .themeAccent))
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
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.themeText)
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
