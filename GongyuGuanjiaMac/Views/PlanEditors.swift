import SwiftUI
import SwiftData

// MARK: - 计划编辑器（收租/包租周期计划；与 iOS 版「计划」功能对应）
// 收租提醒天数与租期提醒由 RentPlanEditor / RentHouseDetail 承担，
// 此处提供包租月度预算计划编辑。

struct BudgetPlan: Identifiable {
    let id = UUID()
    var month: String
    var budget: Double
    var note: String
}

// MARK: - 月度预算计划编辑器

struct BudgetPlanEditor: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var plans: [BudgetPlan] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("月度预算计划")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Text("为每个月设定包租支出预算，汇总页按预算对比实际支出。")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.themeText3)

            if plans.isEmpty {
                Text("暂无计划，点下方「添加」创建")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.themeText3)
                    .padding(.vertical, 12)
            } else {
                List {
                    ForEach(plans) { plan in
                        HStack {
                            Text(plan.month)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 80, alignment: .leading)
                            Text("¥\(FormatKit.money(plan.budget))")
                                .font(.system(size: 14, weight: .semibold))
                            Text(plan.note)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.themeText3)
                            Spacer()
                            Button("删除") {
                                plans.removeAll { $0.id == plan.id }
                                save()
                            }
                            .macSecondaryButton()
                        }
                        .padding(.vertical, 3)
                    }
                }
                .frame(height: 220)
            }

            HStack {
                Button("添加计划") {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM"
                    let month = df.string(from: Date())
                    plans.append(BudgetPlan(month: month, budget: 0, note: ""))
                    save()
                }
                .macSecondaryButton()
                Spacer()
                Button("关闭") { onClose() }
                    .macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func save() {
        // 持久化：预算计划存 UserDefaults（轻量，不进 SwiftData）
        let data = plans.map { ["month": $0.month, "budget": $0.budget, "note": $0.note] }
        if let encoded = try? JSONSerialization.data(withJSONObject: data) {
            UserDefaults.standard.set(encoded, forKey: "budget.plans.v1")
        }
    }
}
