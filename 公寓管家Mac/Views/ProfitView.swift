import SwiftUI
import SwiftData

// MARK: - 汇总（成交/收租/包租 财务统计）

struct ProfitView: View {
    @ObservedObject var manager: DataManager

    @State private var month = Date()

    private var deals: [DealRecord] { manager.deals }
    private var payouts: [PayoutRecord] { manager.payouts }
    private var properties: [Property] { manager.properties }

    private var yearMonth: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        return df.string(from: month)
    }

    /// 当月成交
    private var monthDeals: [DealRecord] {
        deals.filter { Calendar.current.isDate($0.dealDate, equalTo: month, toGranularity: .month) }
    }

    private var monthCommission: Double { monthDeals.reduce(0) { $0 + $1.commission } }
    private var monthFee: Double { monthDeals.reduce(0) { $0 + $1.fee } }
    private var monthPayouts: [PayoutRecord] {
        payouts.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    private var monthPayoutSum: Double { monthPayouts.reduce(0) { $0 + $1.amount } }
    private var monthProfit: Double { monthCommission + monthFee - monthPayoutSum }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("汇总")
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                Button {
                    month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.left")
                }
                .macSecondaryButton()
                Text(yearMonth)
                    .font(.system(size: 14, weight: .semibold))
                Button {
                    month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.right")
                }
                .macSecondaryButton()
                Button("本月") { month = Date() }
                    .macSecondaryButton()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 本月指标
                    HStack(spacing: 12) {
                        StatCard(title: "成交数", value: "\(monthDeals.count)", icon: "doc.text.fill", color: .themeAccent) {}
                        StatCard(title: "佣金收入", value: "¥\(FormatKit.money(monthCommission))", icon: "yensign.circle.fill", color: .themeBlue) {}
                        StatCard(title: "杂费收入", value: "¥\(FormatKit.money(monthFee))", icon: "plus.circle.fill", color: .purple) {}
                        StatCard(title: "支出", value: "¥\(FormatKit.money(monthPayoutSum))", icon: "minus.circle.fill", color: .themeDanger) {}
                        StatCard(title: "净结余", value: "¥\(FormatKit.money(monthProfit))", icon: "chart.line.uptrend.xyaxis", color: monthProfit >= 0 ? .themeAccent : .themeDanger) {}
                    }

                    // 成交明细
                    VStack(alignment: .leading, spacing: 8) {
                        Text("成交明细（当月）")
                            .font(.system(size: 14, weight: .semibold))
                        if monthDeals.isEmpty {
                            Text("当月暂无成交")
                                .font(.system(size: 12))
                                .foregroundColor(.themeText3)
                        } else {
                            Table(monthDeals) {
                                TableColumn("日期") { Text(FormatKit.dateStr($0.dealDate)) }.width(100)
                                TableColumn("房号") { Text($0.roomNo) }.width(80)
                                TableColumn("类型") { Text($0.dealType) }.width(70)
                                TableColumn("金额") { Text("¥\(FormatKit.money($0.price))") }.width(90)
                                TableColumn("佣金") { Text("¥\(FormatKit.money($0.commission))") }.width(80)
                                TableColumn("杂费") { Text("¥\(FormatKit.money($0.fee))") }.width(80)
                                TableColumn("付款方") { Text($0.paidBy) }.width(80)
                            }
                            .frame(height: 180)
                        }
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    // 支出明细
                    VStack(alignment: .leading, spacing: 8) {
                        Text("支出明细（当月）")
                            .font(.system(size: 14, weight: .semibold))
                        if monthPayouts.isEmpty {
                            Text("当月暂无支出")
                                .font(.system(size: 12))
                                .foregroundColor(.themeText3)
                        } else {
                            ForEach(monthPayouts) { pay in
                                HStack {
                                    Text(FormatKit.dateStr(pay.date)).font(.system(size: 12))
                                    Text(pay.category).font(.system(size: 12))
                                    Text("¥\(FormatKit.money(pay.amount))").font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Text(pay.remark).font(.system(size: 11)).foregroundColor(.themeText3)
                                }
                                .padding(.vertical, 3)
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
        .background(Color.themeBg)
    }
}
