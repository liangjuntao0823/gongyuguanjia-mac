import SwiftUI
import SwiftData

// MARK: - 工作台（对齐 iOS：顶栏用户区 + 快捷操作(打开编辑表单) + KPI看板 + 待办事项 + 未收租提醒 + 包租房付租提醒 + 即将到期 + 已刷新）
// Mac 标准：所有详情/弹窗带明确关闭按钮，不依赖滑屏手势

struct DashboardView: View {
    @ObservedObject var manager: DataManager

    // MARK: 快捷操作（全部打开对应编辑表单，iOS 同款）
    @State private var showAddDeal = false
    @State private var showAddIncome = false
    @State private var showAddExpense = false
    @State private var showAddPayout = false
    @State private var showAddTodo = false
    @State private var showAddRent = false
    @State private var showAddHouse = false
    @State private var showAllTodos = false
    @State private var editingTodo: TodoItem?
    @State private var completingTodo: TodoItem?

    // MARK: 未收租 / 包租付租 快捷操作
    @State private var quickCollectProperty: Property?
    @State private var quickCollectRent = ""
    @State private var quickPayPayout: PayoutRecord?
    @State private var quickPayAmount = ""
    @State private var quickPayMonth = 0
    @State private var quickPayRecordMonth = 0
    @State private var viewingProperty: Property?
    @State private var viewingPayout: PayoutRecord?

    // MARK: 折叠状态（与 iOS 同 key）
    @AppStorage("dashboardQuickActionsCollapsed") private var quickActionsCollapsed = false
    @AppStorage("dashboardKpiCollapsed") private var kpiCollapsed = false
    @AppStorage("dashboardTodosCollapsed") private var todosCollapsed = false
    @AppStorage("dashboardRentReminderCollapsed") private var rentReminderCollapsed = false
    @AppStorage("dashboardPayoutReminderCollapsed") private var payoutReminderCollapsed = false
    @AppStorage("dashboardExpiryCollapsed") private var expiryCollapsed = false

    // MARK: 顶栏
    @State private var currentTime = Date()
    @State private var showRefreshTip = false
    @State private var userTitle = "A0-米兰租赁梁涛13288251132"
    @State private var userSubtitle = "选择大于一切，专业省心租好房"
    @State private var editText = ""
    @State private var showEditTitle = false
    @State private var showEditSubtitle = false
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    // MARK: 计算属性

    private var stats: DashboardStats { manager.dashboardStats() }

    private var pendingTodos: [TodoItem] {
        manager.todos.filter { $0.isDeleted != true && !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var currentMonth: Int {
        Calendar.current.component(.month, from: currentTime)
    }

    private var timeRemainingInMonth: (days: Int, hours: Int) {
        let calendar = Calendar.current
        let now = currentTime
        var components = calendar.dateComponents([.year, .month], from: now)
        components.month = (components.month ?? 1) + 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let nextMonth = calendar.date(from: components) else { return (0, 0) }
        let diff = calendar.dateComponents([.day, .hour], from: now, to: nextMonth)
        return (diff.day ?? 0, diff.hour ?? 0)
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: currentTime)
    }

    private var dateStringShort: String {
        let f = DateFormatter(); f.dateFormat = "M月d日 EEE"; f.locale = Locale(identifier: "zh_CN")
        return f.string(from: currentTime)
    }

    // MARK: 未收租提醒（对齐 iOS：逾期或3天内；金额取本月记录或租金+预存；需结算水电标记）

    private var rentReminders: [RentReminder] { loadRentReminders() }
    private var payoutReminders: [PayoutReminder] { loadPayoutReminders() }

    private func loadRentReminders() -> [RentReminder] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        var reminders: [RentReminder] = []
        for prop in manager.properties where prop.isDeleted != true {
            if prop.isTerminated { continue }
            let dueDay = prop.rentDueDay
            // 目标应收月：当月未收则当月；已收则下一期
            let thisMonthPaid = prop.monthlyRentRecords.contains {
                $0.year == currentYear && $0.month == currentMonth && $0.isPaid
            }
            var targetYear = currentYear
            var targetMonth = currentMonth
            if thisMonthPaid {
                targetMonth += 1
                if targetMonth > 12 { targetMonth = 1; targetYear += 1 }
            }
            // 到期日差（按目标月）
            var comps = DateComponents()
            comps.year = targetYear; comps.month = targetMonth; comps.day = dueDay
            guard let dueDate = calendar.date(from: comps) else { continue }
            let daysDiff = calendar.dateComponents([.day], from: now, to: dueDate).day ?? 0
            let isOverdue = daysDiff < 0
            let overdueDays = isOverdue ? -daysDiff : 0
            let daysUntilDue = isOverdue ? 0 : daysDiff

            if isOverdue || daysUntilDue <= 3 {
                let utilityRecord = settlementRecord(for: prop, year: targetYear, month: targetMonth)
                let needUtilitySettlement = utilityRecord != nil && !utilityRecord!.isSettled
                let amount = prop.monthlyRentRecords.first { $0.year == targetYear && $0.month == targetMonth }?.amount ?? (prop.rent + prop.prepayment)
                reminders.append(RentReminder(property: prop, roomNumber: prop.roomNumber, landlord: prop.landlord,
                                              amount: amount, dueDay: dueDay, daysUntilDue: daysUntilDue,
                                              isOverdue: isOverdue, overdueDays: overdueDays, needUtility: needUtilitySettlement))
            }
        }
        return reminders.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue && !b.isOverdue }
            if a.isOverdue && b.isOverdue { return a.overdueDays > b.overdueDays }
            return a.daysUntilDue < b.daysUntilDue
        }
    }

    private func settlementRecord(for prop: Property, year: Int, month: Int) -> UtilitySettlementRecord? {
        let cal = Calendar.current
        return prop.utilitySettlementRecords.first { rec in
            guard let d = rec.dueDate else { return false }
            return cal.component(.year, from: d) == year && cal.component(.month, from: d) == month
        }
    }

    // MARK: 包租房付租提醒（对齐 iOS：逾期或7天内；金额取记录或月租×期数）

    private func periodMonth(for payout: PayoutRecord, index: Int) -> Int {
        switch payout.paymentMethod {
        case "季付": return (index + 1) * 3
        case "半年付": return (index + 1) * 6
        case "年付": return 12
        default: return index + 1
        }
    }

    private func loadPayoutReminders() -> [PayoutReminder] {
        let calendar = Calendar.current
        let now = Date()
        var reminders: [PayoutReminder] = []

        for payout in manager.payouts where payout.isDeleted != true {
            let startDate = payout.leaseStartDate
            let startMonth = calendar.component(.month, from: startDate)
            let startDay = calendar.component(.day, from: startDate)
            let periodCount = payout.paymentMethod == "月付" ? 12 : payout.paymentMethod == "季付" ? 4 : payout.paymentMethod == "半年付" ? 2 : 1
            let periodMonths = 12 / periodCount

            for i in 0..<periodCount {
                let recordMonth = periodMonth(for: payout, index: i)
                var displayMonth = startMonth + i * periodMonths
                if displayMonth > 12 { displayMonth = ((displayMonth - 1) % 12) + 1 }

                let record = payout.monthlyPayouts.first { $0.month == recordMonth }
                if record == nil || !record!.isPaid {
                    let defaultAmount = (payout.monthlyRent ?? 0) * Double(periodMonths)
                    let amount = (record?.amount ?? 0) > 0 ? record!.amount : defaultAmount

                    var dateComps = DateComponents()
                    dateComps.year = calendar.component(.year, from: startDate) + (startMonth + i * periodMonths - 1) / 12
                    dateComps.month = displayMonth
                    dateComps.day = startDay
                    let payDate = calendar.date(from: dateComps) ?? startDate

                    let isOverdue = payDate < now
                    let rawDays = calendar.dateComponents([.day], from: now, to: payDate).day ?? 0
                    let daysDiff = abs(rawDays)

                    if isOverdue || rawDays <= 7 {
                        reminders.append(PayoutReminder(payout: payout, roomNumber: payout.roomNumber,
                                                        paymentMethod: payout.paymentMethod, amount: amount,
                                                        payMonth: displayMonth, recordMonth: recordMonth,
                                                        payDay: startDay, isOverdue: isOverdue, daysDiff: daysDiff))
                    }
                    break
                }
            }
        }
        return reminders.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue && !b.isOverdue }
            if a.isOverdue && b.isOverdue { return a.daysDiff > b.daysDiff }
            return a.daysDiff < b.daysDiff
        }
    }

    // MARK: 快捷收租保存（对齐 iOS：更新或新增本月收租记录）

    private func saveQuickCollect(property: Property) {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        let rentAmount = Double(quickCollectRent) ?? property.rent
        if let existing = property.monthlyRentRecords.first(where: { $0.year == currentYear && $0.month == currentMonth }) {
            existing.amount = rentAmount
            existing.isPaid = true
            existing.paidDate = now
        } else {
            let record = RentMonthRecord(year: currentYear, month: currentMonth, amount: rentAmount, isPaid: true)
            record.paidDate = now
            property.monthlyRentRecords.append(record)
        }
        try? manager.mainContext.save()
        manager.refreshData()
        quickCollectProperty = nil
        MacToastCenter.show("已记录 \(property.roomNumber) 本月收租 ¥\(Int(rentAmount))")
    }

    // MARK: 快捷付租保存（对齐 iOS）

    private func saveQuickPay(payout: PayoutRecord) {
        let record = payout.monthlyPayouts.first { $0.month == quickPayRecordMonth }
        if let r = record {
            r.isPaid = true
            r.paidDate = Date()
            r.amount = Double(quickPayAmount) ?? r.amount
        } else {
            let newRecord = PayoutMonthRecord(month: quickPayRecordMonth, amount: Double(quickPayAmount) ?? 0, isPaid: true)
            newRecord.paidDate = Date()
            manager.mainContext.insert(newRecord)
            payout.monthlyPayouts.append(newRecord)
        }
        try? manager.mainContext.save()
        manager.refreshData()
        quickPayPayout = nil
        MacToastCenter.show("已记录 \(payout.roomNumber) \(quickPayMonth)月付租")
    }

    // MARK: 即将到期天数

    private func daysUntilExpiry(_ prop: Property) -> Int? {
        let f = DateFormatter(); f.dateFormat = "yyyy.M.d"
        guard let end = f.date(from: prop.leaseEnd) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: end).day
    }

    // MARK: 顶栏用户信息

    private func loadUserProfile() {
        let d = UserDefaults.standard
        if let t = d.string(forKey: "dashboard.userTitle"), !t.isEmpty { userTitle = t }
        if let s = d.string(forKey: "dashboard.userSubtitle"), !s.isEmpty { userSubtitle = s }
    }
    private func saveUserProfile() {
        let d = UserDefaults.standard
        d.set(userTitle, forKey: "dashboard.userTitle")
        d.set(userSubtitle, forKey: "dashboard.userSubtitle")
    }

    // MARK: - Body

    // MARK: 工作台分区（拆分子视图，避免编译器类型检查超时）

    @ViewBuilder private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            refreshTipRow
            quickActionsSection
            kpiSection
            todoSection
            rentReminderSection
            payoutReminderSection
            expiringSection
            refreshButtonRow
        }
        .padding(18)
    }

    @ViewBuilder private var refreshTipRow: some View {
                    if showRefreshTip {
                        HStack {
                            Spacer()
                            Text("已刷新")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.themeAccent)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(Color.themeAccentWeak)
                                .cornerRadius(12)
                            Spacer()
                        }
                    }

    }

    @ViewBuilder private var quickActionsSection: some View {
                    // 快捷操作（8 个，全部打开编辑表单）
                    DashboardSectionCard(title: "快捷操作", subtitle: "", isCollapsed: $quickActionsCollapsed) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            QuickActionItem(icon: "plus.circle.fill", label: "新增成交", color: .themeAccent) { showAddDeal = true }
                            QuickActionItem(icon: "dollarsign.circle.fill", label: "新增收入", color: Color(red: 0.80, green: 0.36, blue: 0.36)) { showAddIncome = true }
                            QuickActionItem(icon: "dollarsign.circle.fill", label: "新增支出", color: Color(red: 0.18, green: 0.55, blue: 0.34)) { showAddExpense = true }
                            QuickActionItem(icon: "arrow.up.circle.fill", label: "新增包租", color: Color(red: 0.42, green: 0.25, blue: 0.63)) { showAddPayout = true }
                            QuickActionItem(icon: "checklist", label: "新增待办", color: .themeAccentDark) { showAddTodo = true }
                            QuickActionItem(icon: "creditcard.fill", label: "新增收租", color: .themeBlue) { showAddRent = true }
                            QuickActionItem(icon: "gauge", label: "管理后台", color: .themeBlue) { openAdmin() }
                            QuickActionItem(icon: "building.2.fill", label: "新增房源", color: .themeAccent) { showAddHouse = true }
                        }
                    }

    }

    @ViewBuilder private var kpiSection: some View {
                    // KPI 看板（6 卡，对齐 iOS）
                    DashboardSectionCard(title: "KPI 看板", subtitle: "", isCollapsed: $kpiCollapsed) {
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                KpiCard(label: "收租房间", value: "\(stats.totalProperties)", unit: "套",
                                        foot: "管理\(stats.activeProperties)套 · 托管包租\(stats.managedProperties)套", style: .normal) {
                                    manager.selectedTab = .rents
                                }
                                KpiCard(label: "即将到期", value: "\(stats.expiringSoon.count)", unit: "套",
                                        foot: "30天内到期",
                                        style: (stats.expiringSoon.count > 0) ? .alert : .normal) {
                                    manager.selectedTab = .rents
                                }
                            }
                            HStack(spacing: 10) {
                                KpiCard(label: "本月中介费", value: "\(Int(stats.monthlyDealFee))", unit: "元",
                                        foot: "本月\(stats.monthlyDeals)单", style: .red) {
                                    manager.selectedTab = .deals
                                }
                                KpiCard(label: "杂项收入", value: "\(Int(stats.monthlyMiscIncome))", unit: "元",
                                        foot: "本月", style: .red) {
                                    manager.selectedTab = .deals
                                }
                            }
                            HStack(spacing: 10) {
                                KpiCard(label: "本月收入", value: "\(Int(stats.monthlyNetIncome))", unit: "元",
                                        foot: "中介费+收入-支出", style: .red) {
                                    manager.selectedTab = .profit
                                }
                                KpiCard(label: "杂项支出", value: "\(Int(stats.monthlyMiscExpense))", unit: "元",
                                        foot: "本月", style: .green) {
                                    manager.selectedTab = .deals
                                }
                            }
                        }
                    }

    }

    @ViewBuilder private var todoSection: some View {
                    // 待办事项
                    DashboardSectionCard(title: "待办事项", subtitle: "\(pendingTodos.count)项", isCollapsed: $todosCollapsed, trailing: {
                        Button("全部待办") { showAllTodos = true }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.themeAccentDark)
                            .buttonStyle(.plain)
                    }) {
                        if pendingTodos.isEmpty {
                            Text("暂无待办事项").font(.system(size: 14)).foregroundColor(.themeText3).padding(.vertical, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(pendingTodos) { item in
                                    HStack(spacing: 10) {
                                        Button {
                                            completingTodo = item
                                        } label: {
                                            Image(systemName: "circle")
                                                .font(.system(size: 16))
                                                .foregroundColor(.gray)
                                        }
                                        .buttonStyle(.plain)
                                        Text(item.content)
                                            .font(.system(size: 15))
                                            .lineLimit(2)
                                            .foregroundColor(.themeText)
                                        Spacer()
                                        if let reminder = item.reminderDate {
                                            Text("⏰ \(reminder.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.system(size: 12)).foregroundColor(.themeText3)
                                        }
                                        Button("编辑") { editingTodo = item }
                                            .font(.system(size: 13))
                                            .foregroundColor(.themeAccent)
                                            .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingTodo = item }
                                    if item.id != pendingTodos.last?.id { Divider() }
                                }
                            }
                        }
                    }

    }

    @ViewBuilder private var rentReminderSection: some View {
                    // 未收租提醒
                    DashboardSectionCard(title: "未收租提醒", subtitle: "\(rentReminders.count)套", isCollapsed: $rentReminderCollapsed) {
                        if rentReminders.isEmpty {
                            Text("暂无未收租提醒").font(.system(size: 14)).foregroundColor(.themeText3).padding(.vertical, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(rentReminders) { reminder in
                                    HStack(spacing: 10) {
                                        VStack(spacing: 2) {
                                            Text("\(reminder.dueDay)").font(.system(size: 17, weight: .bold))
                                            Text("号交租").font(.system(size: 10))
                                        }
                                        .frame(width: 46)
                                        .padding(.vertical, 6)
                                        .background(reminder.isOverdue ? Color(red: 0.99, green: 0.94, blue: 0.94) : Color(red: 0.98, green: 0.95, blue: 0.87))
                                        .cornerRadius(8)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(reminder.roomNumber).font(.system(size: 15, weight: .bold))
                                            Text("房东: \(reminder.landlord)").font(.system(size: 13, weight: .bold)).foregroundColor(.themeText2)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text("¥\(Int(reminder.amount))").font(.system(size: 14, weight: .bold))
                                            if reminder.needUtility {
                                                Text("需结算水电").font(.system(size: 11, weight: .semibold)).foregroundColor(.themeAmber)
                                            }
                                        }
                                        Button("收") {
                                            quickCollectProperty = reminder.property
                                            quickCollectRent = String(Int(reminder.amount))
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(Color.themeAccent))
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                    .onTapGesture { viewingProperty = reminder.property }
                                    if reminder.id != rentReminders.last?.id { Divider() }
                                }
                            }
                        }
                    }

    }

    @ViewBuilder private var payoutReminderSection: some View {
                    // 包租房付租提醒
                    DashboardSectionCard(title: "包租房付租提醒", subtitle: "\(payoutReminders.count)套", isCollapsed: $payoutReminderCollapsed) {
                        if payoutReminders.isEmpty {
                            Text("暂无付租提醒").font(.system(size: 14)).foregroundColor(.themeText3).padding(.vertical, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(payoutReminders) { reminder in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("¥\(Int(reminder.amount))")
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundColor(reminder.isOverdue ? .themeRed : .themeText)
                                            HStack(spacing: 6) {
                                                Text(reminder.roomNumber).font(.system(size: 14, weight: .bold))
                                                Text("· \(reminder.paymentMethod)").font(.system(size: 13)).foregroundColor(.themeText2)
                                            }
                                            Text("\(reminder.payMonth)月\(reminder.payDay)号付")
                                                .font(.system(size: 12))
                                                .foregroundColor(reminder.isOverdue ? .themeRed : .themeText3)
                                        }
                                        Spacer()
                                        Text(reminder.isOverdue ? "已逾期\(reminder.daysDiff)天" : "剩\(reminder.daysDiff)天")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(reminder.isOverdue ? .themeRed : .themeAccentDark)
                                        Button("付") {
                                            quickPayPayout = reminder.payout
                                            quickPayAmount = String(Int(reminder.amount))
                                            quickPayMonth = reminder.payMonth
                                            quickPayRecordMonth = reminder.recordMonth
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(Color.themeAccentDark))
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                    .onTapGesture { viewingPayout = reminder.payout }
                                    if reminder.id != payoutReminders.last?.id { Divider() }
                                }
                            }
                        }
                    }

    }

    @ViewBuilder private var expiringSection: some View {
                    // 即将到期（前 3 套）
                    DashboardSectionCard(title: "即将到期", subtitle: "\(stats.expiringSoon.count)套", isCollapsed: $expiryCollapsed) {
                        if stats.expiringSoon.isEmpty {
                            Text("暂无即将到期房源").font(.system(size: 14)).foregroundColor(.themeText3).padding(.vertical, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(stats.expiringSoon.prefix(3))) { prop in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack(spacing: 8) {
                                                Text(prop.roomNumber).font(.system(size: 19, weight: .bold))
                                                Text("到期:\(prop.leaseEnd)").font(.system(size: 14)).foregroundColor(.themeText2)
                                            }
                                            HStack(spacing: 6) {
                                                Text("房东: \(prop.landlord)")
                                                Text("租金: ¥\(Int(prop.rent))")
                                                Text("押金: ¥\(Int(prop.deposit))")
                                            }
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.themeText3)
                                        }
                                        Spacer()
                                        if let days = daysUntilExpiry(prop) {
                                            Text(days >= 0 ? "还剩\(days)天" : "已超期\(-days)天")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(days >= 0 ? .themeAccentDark : .red)
                                        }
                                    }
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                    .onTapGesture { viewingProperty = prop }
                                    if prop.id != stats.expiringSoon.prefix(3).last?.id { Divider() }
                                }
                            }
                        }
                    }

    }

    @ViewBuilder private var refreshButtonRow: some View {
                    // 刷新
                    HStack {
                        Spacer()
                        Button {
                            refreshDashboard()
                            withAnimation { showRefreshTip = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation { showRefreshTip = false }
                            }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .macSecondaryButton()
                    }
                    .padding(.bottom, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏用户区（对齐 iOS：标题 + 副标题(剩余天数) + 右侧时间日期；拆分子视图避免类型检查超时）
            UserHeaderView(userTitle: userTitle,
                           currentMonth: currentMonth,
                           remainDays: timeRemainingInMonth.days,
                           remainHours: timeRemainingInMonth.hours,
                           timeString: timeString,
                           dateStringShort: dateStringShort,
                           onEditTitle: { editText = userTitle; showEditTitle = true })
            Divider()

            ScrollView {
                dashboardContent
            }
            .background(Color.themeBg)
        }
        .onAppear {
            loadUserProfile()
            currentTime = Date()
        }
        .onReceive(timer) { _ in currentTime = Date() }
        .alert("编辑标题", isPresented: $showEditTitle) {
            TextField("请输入标题", text: $editText)
            Button("取消", role: .cancel) { }
            Button("保存") { userTitle = editText; saveUserProfile() }
        }
        .alert("编辑副标题", isPresented: $showEditSubtitle) {
            TextField("请输入副标题", text: $editText)
            Button("取消", role: .cancel) { }
            Button("保存") { userSubtitle = editText; saveUserProfile() }
        }
        // 快捷操作 → 编辑表单
        .sheet(isPresented: $showAddDeal) { DealEditor(manager: manager, deal: nil) { showAddDeal = false } }
        .sheet(isPresented: $showAddIncome) { MiscEditor(manager: manager, income: nil, expense: nil, isIncome: true) { showAddIncome = false } }
        .sheet(isPresented: $showAddExpense) { MiscEditor(manager: manager, income: nil, expense: nil, isIncome: false) { showAddExpense = false } }
        .sheet(isPresented: $showAddPayout) { PayoutEditor(manager: manager, payout: nil) { showAddPayout = false } }
        .sheet(isPresented: $showAddTodo) { TodoFormView(manager: manager, item: nil) { showAddTodo = false } }
        .sheet(isPresented: $showAddRent) { PropertyEditor(manager: manager, property: nil) { showAddRent = false } }
        .sheet(isPresented: $showAddHouse) { HouseEditView(manager: manager, house: nil) { showAddHouse = false } }
        // 待办
        .sheet(isPresented: $showAllTodos) { TodoViews(manager: manager) { showAllTodos = false } }
        .sheet(item: $editingTodo) { item in TodoFormView(manager: manager, item: item) { editingTodo = nil } }
        .alert("确认已办？", isPresented: Binding(
            get: { completingTodo != nil },
            set: { if !$0 { completingTodo = nil } }
        )) {
            Button("取消", role: .cancel) { completingTodo = nil }
            Button("确认") {
                completingTodo?.isCompleted = true
                completingTodo?.completedDate = Date()
                try? manager.mainContext.save()
                manager.refreshData()
                completingTodo = nil
            }
        } message: {
            Text("完成后将归档到已办。")
        }
        // 提醒详情与快捷收付租
        .sheet(item: $quickCollectProperty) { prop in
            QuickCollectSheet(property: prop, rentText: $quickCollectRent) {
                saveQuickCollect(property: prop)
            }
        }
        .sheet(item: $quickPayPayout) { payout in
            QuickPaySheet(payout: payout, amountText: $quickPayAmount, payMonth: quickPayMonth, recordMonth: quickPayRecordMonth) {
                saveQuickPay(payout: payout)
            }
        }
        .sheet(item: $viewingProperty) { prop in
            PropertyDetailView(manager: manager, property: prop) { viewingProperty = nil }
        }
        .sheet(item: $viewingPayout) { payout in
            PayoutDetailView(manager: manager, payout: payout) { viewingPayout = nil }
        }
    }

    private func refreshDashboard() {
        manager.refreshAll()
    }

    private func openAdmin() {
        let url = CloudConfig.functionURL
        if !url.isEmpty {
            MacBridge.openURL(url)
            MacToastCenter.show("已打开云端管理后台（浏览器）")
        } else {
            MacToastCenter.show("未配置云函数地址，请先在「设置 → 云端/分享设置」中填写")
        }
    }
}

// MARK: - 提醒模型（对齐 iOS）

struct RentReminder: Identifiable {
    let id = UUID()
    let property: Property
    let roomNumber: String
    let landlord: String
    let amount: Double
    let dueDay: Int
    let daysUntilDue: Int
    let isOverdue: Bool
    let overdueDays: Int
    let needUtility: Bool
}

struct PayoutReminder: Identifiable {
    let id = UUID()
    let payout: PayoutRecord
    let roomNumber: String
    let paymentMethod: String
    let amount: Double
    let payMonth: Int
    let recordMonth: Int
    let payDay: Int
    let isOverdue: Bool
    let daysDiff: Int
}

// MARK: - 区块卡（对齐 iOS DashboardSectionCard：标题可折叠）

struct DashboardSectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @Binding var isCollapsed: Bool
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.themeText)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 13)).foregroundColor(.themeText3)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isCollapsed.toggle() } }
            trailing()
        }
        .frame(minHeight: 26)
    }
}

struct DashboardSectionCard<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    @Binding var isCollapsed: Bool
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 0 : 10) {
            DashboardSectionHeader(title: title, subtitle: subtitle, isCollapsed: $isCollapsed, trailing: trailing)
            if !isCollapsed { content() }
        }
        .padding(isCollapsed ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
    }
}

// MARK: - 快捷操作项（对齐 iOS QuickActionItem）

struct QuickActionItem: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.themeText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - KPI 卡片（对齐 iOS KpiCard）

struct KpiCard: View {
    let label: String
    let value: String
    let unit: String
    let foot: String
    let style: KpiStyle
    let action: () -> Void

    enum KpiStyle { case normal, alert, red, green }

    private var valueColor: Color {
        switch style {
        case .alert: return .themeDanger
        case .red: return .themeRed
        case .green: return Color(red: 0.18, green: 0.55, blue: 0.34)
        case .normal: return .themeText
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(label).font(.system(size: 14)).foregroundColor(.themeText2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(valueColor)
                    Text(unit).font(.system(size: 13)).foregroundColor(.themeText3)
                }
                Text(foot).font(.system(size: 12)).foregroundColor(.themeText3).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorder))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 快捷收租弹窗（对齐 iOS QuickCollectSheet）

struct QuickCollectSheet: View {
    let property: Property
    @Binding var rentText: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("快捷收租").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("取消") { dismiss() }.macSecondaryButton()
                Button("保存") {
                    onSave()
                    dismiss()
                }.macPrimaryButton()
            }
            .padding(14)
            Divider()
            Form {
                Section("房源信息") {
                    LabeledContent("房号", value: property.roomNumber)
                    LabeledContent("房东", value: property.landlord)
                }
                Section("收租金额") {
                    TextField("实收租金", text: $rentText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            .padding(14)
            Spacer(minLength: 0)
        }
        .frame(width: 360, height: 320)
    }
}

// MARK: - 快捷付租弹窗（对齐 iOS QuickPaySheet）

struct QuickPaySheet: View {
    let payout: PayoutRecord
    @Binding var amountText: String
    let payMonth: Int
    let recordMonth: Int
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("快捷付租").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("取消") { dismiss() }.macSecondaryButton()
                Button("保存") {
                    onSave()
                    dismiss()
                }.macPrimaryButton()
            }
            .padding(14)
            Divider()
            Form {
                Section("房源信息") {
                    LabeledContent("房号", value: payout.roomNumber)
                    LabeledContent("付款月", value: "\(payMonth)月")
                }
                Section("付租金额") {
                    TextField("实付金额", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            .padding(14)
            Spacer(minLength: 0)
        }
        .frame(width: 360, height: 320)
    }
}

// MARK: - 待办编辑表单（对齐 iOS TodoFormView：内容 + 提醒）

struct TodoFormView: View {
    @ObservedObject var manager: DataManager
    let item: TodoItem?
    let onClose: () -> Void

    @State private var content: String
    @State private var reminderEnabled: Bool
    @State private var reminderDate: Date

    init(manager: DataManager, item: TodoItem?, onClose: @escaping () -> Void) {
        self.manager = manager
        self.item = item
        self.onClose = onClose
        _content = State(initialValue: item?.content ?? "")
        _reminderEnabled = State(initialValue: item?.reminderDate != nil)
        _reminderDate = State(initialValue: item?.reminderDate ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item == nil ? "新增待办" : "编辑待办").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("取消") { onClose() }.macSecondaryButton()
                Button("保存") { save() }
                    .macPrimaryButton()
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            Divider()
            Form {
                Section("待办信息") {
                    TextField("待办内容", text: $content, axis: .vertical)
                        .lineLimit(3...6)
                    Toggle("设置提醒", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("提醒时间", selection: $reminderDate)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(14)
            Spacer(minLength: 0)
        }
        .frame(width: 400, height: 320)
    }

    private func save() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let item {
            item.content = trimmed
            item.reminderDate = reminderEnabled ? reminderDate : nil
            try? manager.mainContext.save()
        } else {
            manager.addTodo(content: trimmed, reminderDate: reminderEnabled ? reminderDate : nil)
        }
        manager.refreshData()
        onClose()
    }
}

// MARK: - 月份倒计时（顶栏副标题，拆分子视图避免类型检查超时）

struct MonthCountdownView: View {
    let month: Int
    let days: Int
    let hours: Int

    var body: some View {
        HStack(spacing: 0) {
            Text("\(month)月还剩").font(.system(size: 14)).foregroundColor(.themeText2)
            Text("\(days)").font(.system(size: 13, weight: .bold)).foregroundColor(.themeAccentDark)
            Text("天").font(.system(size: 14)).foregroundColor(.themeText2)
            Text("\(hours)").font(.system(size: 13, weight: .bold)).foregroundColor(.themeAccentDark)
            Text("小时，加油").font(.system(size: 14)).foregroundColor(.themeText2)
        }
    }
}

// MARK: - 顶栏用户区（对齐 iOS：头像 + 标题 + 剩余天数 + 右侧时间日期）

struct UserHeaderView: View {
    let userTitle: String
    let currentMonth: Int
    let remainDays: Int
    let remainHours: Int
    let timeString: String
    let dateStringShort: String
    let onEditTitle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.91, green: 0.91, blue: 0.91))
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "person.fill").font(.system(size: 20)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 5) {
                Button(action: onEditTitle) {
                    Text(userTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.themeText)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                MonthCountdownView(month: currentMonth, days: remainDays, hours: remainHours)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString).font(.system(size: 20, weight: .bold)).foregroundColor(.themeText)
                Text(dateStringShort).font(.system(size: 14)).foregroundColor(.themeText2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}
