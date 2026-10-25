import SwiftUI
import SwiftData

// MARK: - 回收站（对齐 iOS：分类筛选 + 批量还原/删除 + 分区清空）

enum TrashFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case houses = "房源"
    case deals = "成交"
    case rents = "收租"
    case incomes = "杂项收入"
    case expenses = "杂项支出"
    case payouts = "包租"
    case todos = "待办"
    var id: String { rawValue }
}

struct TrashItem: Identifiable {
    let id = UUID()
    let kind: TrashFilter
    let title: String
    let subtitle: String
    let deletedAt: Date?
    let restore: () -> Void
    let deleteForever: () -> Void
}

struct TrashView: View {
    @ObservedObject var manager: DataManager

    @State private var filter: TrashFilter = .all
    @State private var showClearAllConfirm = false

    private var deletedDeals: [DealRecord] { manager.deals.filter { $0.isDeleted == true }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }
    private var deletedIncomes: [MiscIncome] { manager.miscIncomes.filter { $0.isDeleted == true }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }
    private var deletedExpenses: [MiscExpense] { manager.miscExpenses.filter { $0.isDeleted == true }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }
    private var deletedProperties: [Property] { manager.properties.filter { $0.isDeleted == true }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }
    private var deletedPayouts: [PayoutRecord] { manager.payouts.filter { $0.isDeleted == true }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }
    private var deletedTodos: [TodoItem] { manager.todos.filter { $0.isDeleted == true }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }
    private var deletedHouses: [House] { manager.houses.filter { $0.isDeleted == true }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }

    private var totalCount: Int {
        deletedDeals.count + deletedIncomes.count + deletedExpenses.count +
        deletedProperties.count + deletedPayouts.count + deletedTodos.count + deletedHouses.count
    }

    private var items: [TrashItem] {
        var out: [TrashItem] = []
        func makeRestore(_ kind: TrashFilter) -> () -> Void {
            return {
                MacToastCenter.show("已还原")
                NotificationCenter.default.post(name: .macDataChanged, object: nil)
            }
        }
        func makeDeleteForever(_ kind: TrashFilter) -> () -> Void {
            return {
                MacToastCenter.show("已彻底删除")
                NotificationCenter.default.post(name: .macDataChanged, object: nil)
            }
        }
        let restoreHint = makeRestore
        let deleteHint = makeDeleteForever
        if filter == .all || filter == .houses {
            for h in deletedHouses {
                out.append(TrashItem(kind: .houses, title: h.displayRoomNo, subtitle: "\(h.layout) · 房源", deletedAt: h.deletedAt,
                                     restore: { manager.restoreHouse(h); _ = restoreHint(.houses)() },
                                     deleteForever: { manager.permanentDeleteHouse(h); _ = deleteHint(.houses)() }))
            }
        }
        if filter == .all || filter == .deals {
            for d in deletedDeals {
                out.append(TrashItem(kind: .deals, title: "\(d.roomNumber)", subtitle: "¥\(Int(d.totalFee)) · 成交", deletedAt: d.deletedAt,
                                     restore: { manager.restoreDeal(d); _ = restoreHint(.deals)() },
                                     deleteForever: { manager.permanentDeleteDeal(d); _ = deleteHint(.deals)() }))
            }
        }
        if filter == .all || filter == .incomes {
            for i in deletedIncomes {
                out.append(TrashItem(kind: .incomes, title: i.item, subtitle: "¥\(Int(i.amount)) · 杂项收入", deletedAt: i.deletedAt,
                                     restore: { manager.restoreMiscIncome(i); _ = restoreHint(.incomes)() },
                                     deleteForever: { manager.permanentDeleteMiscIncome(i); _ = deleteHint(.incomes)() }))
            }
        }
        if filter == .all || filter == .expenses {
            for e in deletedExpenses {
                out.append(TrashItem(kind: .expenses, title: e.item, subtitle: "¥\(Int(e.amount)) · 杂项支出", deletedAt: e.deletedAt,
                                     restore: { manager.restoreMiscExpense(e); _ = restoreHint(.expenses)() },
                                     deleteForever: { manager.permanentDeleteMiscExpense(e); _ = deleteHint(.expenses)() }))
            }
        }
        if filter == .all || filter == .rents {
            for p in deletedProperties {
                out.append(TrashItem(kind: .rents, title: p.roomNumber, subtitle: "¥\(Int(p.rent))/月 · 收租房源", deletedAt: p.deletedAt,
                                     restore: { manager.restoreProperty(p); _ = restoreHint(.rents)() },
                                     deleteForever: { manager.permanentDeleteProperty(p); _ = deleteHint(.rents)() }))
            }
        }
        if filter == .all || filter == .payouts {
            for p in deletedPayouts {
                out.append(TrashItem(kind: .payouts, title: p.roomNumber, subtitle: "¥\(Int(p.annualRent))/年 · 包租", deletedAt: p.deletedAt,
                                     restore: { manager.restorePayout(p); _ = restoreHint(.payouts)() },
                                     deleteForever: { manager.permanentDeletePayout(p); _ = deleteHint(.payouts)() }))
            }
        }
        if filter == .all || filter == .todos {
            for t in deletedTodos {
                out.append(TrashItem(kind: .todos, title: t.content, subtitle: "待办", deletedAt: t.deletedAt,
                                     restore: { manager.restoreTodo(t); _ = restoreHint(.todos)() },
                                     deleteForever: { manager.permanentDeleteTodo(t); _ = deleteHint(.todos)() }))
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("回收站").font(.system(size: 17, weight: .bold))
                Text("共 \(totalCount) 条")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText3)
                Spacer()
                Button("清空回收站") { showClearAllConfirm = true }
                    .macSecondaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            // 分类筛选标签
            HStack(spacing: 8) {
                ForEach(TrashFilter.allCases) { item in
                    let isSelected = filter == item
                    Button {
                        filter = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(isSelected ? Color.themeAccent : Color(red: 0.93, green: 0.94, blue: 0.95))
                            .foregroundColor(isSelected ? .white : .themeText)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(12)

            Divider()

            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("回收站为空")
                        .font(.system(size: 14))
                        .foregroundColor(.themeText3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: kindIcon(item.kind))
                            .foregroundColor(kindColor(item.kind))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.subtitle).font(.system(size: 11)).foregroundColor(.themeText3)
                        }
                        Spacer()
                        Text(item.deletedAt.map { FormatKit.dateStr($0) } ?? "")
                            .font(.system(size: 11))
                            .foregroundColor(.themeText3)
                        Button("还原") { item.restore() }.macSecondaryButton()
                        Button {
                            item.deleteForever()
                        } label: { Image(systemName: "xmark.bin.fill") }
                        .macSecondaryButton()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .confirmationDialog("清空回收站将彻底删除全部 \(totalCount) 条记录（房源媒体文件一并删除），且无法恢复。",
                            isPresented: $showClearAllConfirm) {
            Button("彻底清空", role: .destructive) { clearAll() }
            Button("取消", role: .cancel) { showClearAllConfirm = false }
        }
    }

    private func kindIcon(_ kind: TrashFilter) -> String {
        switch kind {
        case .houses: return "house"
        case .deals: return "doc.text"
        case .rents: return "banknote"
        case .incomes: return "plus.circle"
        case .expenses: return "minus.circle"
        case .payouts: return "briefcase"
        case .todos: return "checklist"
        case .all: return "trash"
        }
    }
    private func kindColor(_ kind: TrashFilter) -> Color {
        switch kind {
        case .houses: return .themeAccent
        case .deals: return .themeDanger
        case .rents: return .themeWarning
        case .incomes: return .themeAccentDark
        case .expenses: return .themeRed
        case .payouts: return .purple
        case .todos: return .themeBlue
        case .all: return .gray
        }
    }
    private func clearAll() {
        for h in deletedHouses { manager.permanentDeleteHouse(h) }
        for d in deletedDeals { manager.permanentDeleteDeal(d) }
        for i in deletedIncomes { manager.permanentDeleteMiscIncome(i) }
        for e in deletedExpenses { manager.permanentDeleteMiscExpense(e) }
        for p in deletedProperties { manager.permanentDeleteProperty(p) }
        for p in deletedPayouts { manager.permanentDeletePayout(p) }
        for t in deletedTodos { manager.permanentDeleteTodo(t) }
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
        MacToastCenter.show("回收站已清空")
    }
}
