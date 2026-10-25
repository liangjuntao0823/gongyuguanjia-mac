import SwiftUI
import SwiftData

// MARK: - 汇总板块（对齐 iOS：月度汇总列表 + 年度合计卡片）

struct MonthlySummary: Identifiable {
    let month: Int
    let year: Int
    let dealCount: Int
    let agentFee: Double
    let miscIncome: Double
    let miscExpense: Double
    let netIncome: Double

    var id: String { "\(year)-\(month)" }
}

struct ProfitView: View {
    @ObservedObject var manager: DataManager

    private var monthlySummaries: [MonthlySummary] {
        let cal = Calendar.current
        var summaries: [MonthlySummary] = []
        // 从最早有记录月份到当前月
        let now = Date()
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)
        var earliestYear = currentYear
        var earliestMonth = currentMonth
        let deals = manager.deals.filter { $0.isDeleted != true }
        let incomes = manager.miscIncomes.filter { $0.isDeleted != true }
        let expenses = manager.miscExpenses.filter { $0.isDeleted != true }
        for d in deals {
            let y = cal.component(.year, from: d.date)
            let m = cal.component(.month, from: d.date)
            if y < earliestYear || (y == earliestYear && m < earliestMonth) { earliestYear = y; earliestMonth = m }
        }
        for i in incomes {
            let y = cal.component(.year, from: i.date)
            let m = cal.component(.month, from: i.date)
            if y < earliestYear || (y == earliestYear && m < earliestMonth) { earliestYear = y; earliestMonth = m }
        }
        for e in expenses {
            let y = cal.component(.year, from: e.date)
            let m = cal.component(.month, from: e.date)
            if y < earliestYear || (y == earliestYear && m < earliestMonth) { earliestYear = y; earliestMonth = m }
        }

        var y = earliestYear
        var m = earliestMonth
        var guardCount = 0
        while (y < currentYear || (y == currentYear && m <= currentMonth)) && guardCount < 240 {
            let stats = manager.monthlyStats(month: m, year: y)
            let dealCount = deals.filter {
                cal.component(.year, from: $0.date) == y && cal.component(.month, from: $0.date) == m
            }.count
            summaries.append(MonthlySummary(month: m, year: y, dealCount: dealCount,
                                            agentFee: stats.income, miscIncome: 0, miscExpense: 0, netIncome: stats.net))
            m += 1
            if m > 12 { m = 1; y += 1 }
            guardCount += 1
        }
        return summaries.reversed()
    }

    private var filteredTotal: MonthlySummary {
        let cal = Calendar.current
        let now = Date()
        let thisYear = cal.component(.year, from: now)
        let deals = manager.deals.filter { $0.isDeleted != true && cal.component(.year, from: $0.date) == thisYear }
        let incomes = manager.miscIncomes.filter { $0.isDeleted != true && cal.component(.year, from: $0.date) == thisYear }
        let expenses = manager.miscExpenses.filter { $0.isDeleted != true && cal.component(.year, from: $0.date) == thisYear }
        let agentFee = deals.reduce(0) { $0 + $1.totalFee }
        let miscIncome = incomes.reduce(0) { $0 + $1.amount }
        let miscExpense = expenses.reduce(0) { $0 + $1.amount }
        return MonthlySummary(month: 0, year: thisYear, dealCount: deals.count, agentFee: agentFee,
                             miscIncome: miscIncome, miscExpense: miscExpense,
                             netIncome: agentFee + miscIncome - miscExpense)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("汇总 · \(filteredTotal.year)年")
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                Button("刷新") {
                    NotificationCenter.default.post(name: .macDataChanged, object: nil)
                    MacToastCenter.show("已刷新")
                }
                .macSecondaryButton()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 年度合计卡片
                    HStack(spacing: 10) {
                        SummaryCard(title: "成交", value: "\(filteredTotal.dealCount)单",
                                    color: Color(hex: "F59E0B"), bgColor: Color(hex: "FFF3E0"))
                        SummaryCard(title: "中介费", value: "¥\(Int(filteredTotal.agentFee))",
                                    color: Color(hex: "F59E0B"), bgColor: Color(hex: "FFF3E0"))
                        SummaryCard(title: "杂项收入", value: "¥\(Int(filteredTotal.miscIncome))",
                                    color: .themeRed, bgColor: Color(hex: "FDECEC"))
                        SummaryCard(title: "杂项支出", value: "¥\(Int(filteredTotal.miscExpense))",
                                    color: .themeAccentDark, bgColor: Color(hex: "E8F5E9"))
                        SummaryCard(title: "净总收入", value: "¥\(Int(filteredTotal.netIncome))",
                                    color: .themeRed, bgColor: Color(hex: "FDECEC"))
                    }

                    // 月度列表
                    VStack(alignment: .leading, spacing: 8) {
                        Text("月度明细（最近在前）")
                            .font(.system(size: 14, weight: .semibold))
                        if monthlySummaries.isEmpty {
                            Text("暂无统计数据")
                                .font(.system(size: 12))
                                .foregroundColor(.themeText3)
                                .padding(.vertical, 12)
                        } else {
                            Table(monthlySummaries) {
                                TableColumn("月份") { s in
                                    Text(s.year == Calendar.current.component(.year, from: Date()) ? "\(s.month)月" : "\(s.year)年\(s.month)月")
                                }
                                .width(90)
                                TableColumn("成交") { s in Text("\(s.dealCount)单") }.width(60)
                                TableColumn("中介费") { s in Text("¥\(Int(s.agentFee))") }.width(90)
                                TableColumn("杂项收入") { s in Text("¥\(Int(s.miscIncome))") }.width(90)
                                TableColumn("杂项支出") { s in Text("¥\(Int(s.miscExpense))") }.width(90)
                                TableColumn("净收入") { s in
                                    Text("¥\(Int(s.netIncome))")
                                        .foregroundColor(s.netIncome >= 0 ? .themeAccentDark : .themeRed)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .width(100)
                            }
                            .frame(minHeight: 220)
                        }
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    Spacer(minLength: 16)
                }
                .padding(16)
            }
        }
        .background(Color.themeBg)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let color: Color
    let bgColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundColor(.themeText3)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(bgColor)
        .cornerRadius(10)
    }
}
