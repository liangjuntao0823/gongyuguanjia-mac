import SwiftUI
import SwiftData

// MARK: - 待办事项（Mac 桌面版，功能对齐 iOS v1.x 全部待办）

struct TodoViews: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var selectedStatus = 0          // 0 未办 / 1 已办
    @State private var newTitle = ""
    @State private var isSorting = false
    @State private var editingItem: TodoItem?
    @State private var previewItem: TodoItem?
    @State private var completingItem: TodoItem?
    @State private var deletingItem: TodoItem?
    @State private var showNewForm = false

    private var activeItems: [TodoItem] {
        manager.todos.filter { $0.isDeleted != true }
    }

    private var visibleItems: [TodoItem] {
        let filtered = activeItems.filter {
            $0.isCompleted == (selectedStatus == 1)
                && (searchText.isEmpty || $0.content.localizedCaseInsensitiveContains(searchText))
        }
        if selectedStatus == 1 {
            // 已办结：按完成日期降序
            return filtered.sorted { ($0.completedDate ?? $0.createdDate) > ($1.completedDate ?? $1.createdDate) }
        }
        // 未办：按手动拖动排序
        return filtered.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdDate > $1.createdDate
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Text("待办事项")
                    .font(.system(size: 19, weight: .bold))
                Text("未办 \(uncompletedCount) · 已办 \(completedCount)")
                    .font(.system(size: 13))
                    .foregroundColor(.themeText3)
                Spacer()
                if selectedStatus == 0 && searchText.isEmpty {
                    Button { withAnimation { isSorting.toggle() } } label: {
                        Label(isSorting ? "完成排序" : "排序", systemImage: "arrow.up.arrow.down")
                    }
                    .macSecondaryButton()
                }
                Button("关闭") { onClose() }
                    .macSecondaryButton()
            }
            .padding(14)
            .background(Color.themeHeader)

            // 快速添加 + 搜索 + 筛选
            HStack(spacing: 10) {
                TextField("输入待办内容，回车快速添加（提醒请点右侧表单）…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { quickAdd() }
                Button { quickAdd() } label: { Label("添加", systemImage: "plus") }
                    .macSecondaryButton()
                Button { showNewForm = true } label: { Label("新增表单", systemImage: "calendar.badge.clock") }
                    .macPrimaryButton()
                Spacer()
                Picker("状态", selection: $selectedStatus) {
                    Text("未办").tag(0)
                    Text("已办").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.themeText3)
                TextField("搜索待办内容", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.themeText3) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Divider().padding(.top, 10)

            if visibleItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: selectedStatus == 1 ? "checkmark.seal" : "checklist")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text(selectedStatus == 1 ? "暂无已办事项" : "暂无待办")
                        .font(.system(size: 15))
                        .foregroundColor(.themeText3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleItems) { item in
                        TodoRow(item: item, showComplete: !item.isCompleted, isSorting: isSorting && selectedStatus == 0,
                                onMoveUp: { move(item, up: true) }, onMoveDown: { move(item, up: false) },
                                onComplete: { completingItem = item },
                                onEdit: { editingItem = item }, onDelete: { deletingItem = item })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if item.isCompleted { previewItem = item } else { editingItem = item }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color.themeBg)
        .frame(minWidth: 720, minHeight: 520)
        .sheet(isPresented: $showNewForm) {
            TodoItemFormView(manager: manager, item: nil, onClose: { showNewForm = false })
        }
        .sheet(item: $editingItem) { item in
            TodoItemFormView(manager: manager, item: item, onClose: { editingItem = nil })
        }
        .sheet(item: $previewItem) { item in
            TodoItemFormView(manager: manager, item: item, readOnly: true, onClose: { previewItem = nil })
        }
        // 完成确认
        .alert("确认已办？", isPresented: Binding(get: { completingItem != nil }, set: { if !$0 { completingItem = nil } })) {
            Button("取消", role: .cancel) { completingItem = nil }
            Button("确认已办") {
                if let item = completingItem { manager.toggleTodo(item) }
                completingItem = nil
            }
        } message: { Text("该事项将移到「已办」列表。") }
        // 删除确认
        .alert("确认删除？", isPresented: Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } })) {
            Button("取消", role: .cancel) { deletingItem = nil }
            Button("确定删除", role: .destructive) {
                if let item = deletingItem { manager.softDeleteTodo(item) }
                deletingItem = nil
            }
        } message: { Text("删除后可在回收站找回。") }
    }

    private var uncompletedCount: Int { activeItems.filter { !$0.isCompleted }.count }
    private var completedCount: Int { activeItems.filter { $0.isCompleted }.count }

    private func quickAdd() {
        manager.addTodo(content: newTitle)
        newTitle = ""
    }

    /// 未办列表上移/下移（按 sortOrder 重排）
    private func move(_ item: TodoItem, up: Bool) {
        var ordered = visibleItems
        guard let idx = ordered.firstIndex(where: { $0.id == item.id }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard target >= 0 && target < ordered.count else { return }
        ordered.swapAt(idx, target)
        for (index, it) in ordered.enumerated() { it.sortOrder = index }
        try? manager.mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
    }
}

// MARK: - 待办行

struct TodoRow: View {
    let item: TodoItem
    let showComplete: Bool
    let isSorting: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private func text(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy.M.d"
        return f.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            // 提醒标记
            if item.reminderDate != nil && !item.isCompleted {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 9, height: 9)
                    .frame(width: 12, height: 12, alignment: .leading)
            } else {
                Color.clear.frame(width: 12, height: 12)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .font(.system(size: 15, weight: .semibold))
                    .strikethrough(item.isCompleted)
                    .foregroundColor(item.isCompleted ? .themeText3 : .themeText)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(text(item.createdDate))
                        .font(.system(size: 13))
                        .foregroundColor(.themeText3)
                    if let reminder = item.reminderDate, !item.isCompleted {
                        Text("⏰ \(reminder.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }
            }
            Spacer()
            if isSorting {
                HStack(spacing: 4) {
                    Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                        .buttonStyle(.plain).foregroundColor(.themeText2).help("上移")
                    Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain).foregroundColor(.themeText2).help("下移")
                }
            }
            if showComplete {
                Button("已办", action: onComplete)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("已办结")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                    Text(text(item.completedDate))
                        .font(.system(size: 13))
                        .foregroundColor(.themeText3)
                }
            }
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.themeText2)
            }
            .buttonStyle(.plain)
            .help("编辑")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.themeDanger)
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.vertical, 5)
    }
}

// MARK: - 待办表单（新增 / 编辑 / 预览）

struct TodoItemFormView: View {
    @ObservedObject var manager: DataManager
    let item: TodoItem?
    var readOnly: Bool = false
    let onClose: () -> Void

    @State private var createdDate: Date
    @State private var content: String
    @State private var reminderEnabled: Bool
    @State private var reminderDate: Date
    @State private var restoreConfirm = false

    init(manager: DataManager, item: TodoItem?, readOnly: Bool = false, onClose: @escaping () -> Void) {
        self.manager = manager
        self.item = item
        self.readOnly = readOnly
        self.onClose = onClose
        _createdDate = State(initialValue: item?.createdDate ?? Date())
        _content = State(initialValue: item?.content ?? "")
        _reminderEnabled = State(initialValue: item?.reminderDate != nil)
        _reminderDate = State(initialValue: item?.reminderDate ?? Date().addingTimeInterval(3600))
    }

    private var isNew: Bool { item == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(readOnly ? "待办预览" : (isNew ? "新增待办" : "编辑待办"))
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.gray) }
                    .buttonStyle(.plain)
            }

            if readOnly {
                infoRow("新增时间", createdDate.formatted(date: .numeric, time: .omitted))
                Text(content)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let reminder = item?.reminderDate {
                    infoRow("提醒时间", reminder.formatted(date: .numeric, time: .shortened))
                }
                if let completed = item?.completedDate {
                    infoRow("办理日期", completed.formatted(date: .numeric, time: .omitted))
                }
            } else {
                HStack(spacing: 12) {
                    Text("新增时间").font(.system(size: 14)).foregroundColor(.themeText3).frame(width: 70, alignment: .leading)
                    DatePicker("", selection: $createdDate, displayedComponents: .date)
                        .labelsHidden()
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("待办内容").font(.system(size: 14)).foregroundColor(.themeText3)
                    TextEditor(text: $content)
                        .font(.system(size: 15))
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "CCCCCC")))
                }
                Toggle("设置提醒", isOn: $reminderEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 14))
                if reminderEnabled {
                    HStack(spacing: 12) {
                        Text("提醒时间").font(.system(size: 14)).foregroundColor(.themeText3).frame(width: 70, alignment: .leading)
                        DatePicker("", selection: $reminderDate)
                            .labelsHidden()
                    }
                }
            }

            Divider()

            HStack {
                if readOnly, item?.isCompleted == true {
                    Button("恢复未办理") { restoreConfirm = true }
                        .macSecondaryButton()
                    Spacer()
                    Button("关闭") { onClose() }.macPrimaryButton()
                } else {
                    Spacer()
                    Button("取消") { onClose() }.macSecondaryButton()
                    Button("保存") { save() }
                        .macPrimaryButton()
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 430)
        .alert("恢复未办理？", isPresented: $restoreConfirm) {
            Button("取消", role: .cancel) { }
            Button("确认恢复") {
                if let item {
                    manager.toggleTodo(item)
                    onClose()
                }
            }
        } message: { Text("该事项将回到未办列表。") }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.system(size: 13)).foregroundColor(.themeText3)
            Text(value).font(.system(size: 14, weight: .medium))
            Spacer()
        }
    }

    private func save() {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item {
            manager.updateTodo(item, content: text, createdDate: createdDate, reminderDate: reminderEnabled ? reminderDate : nil)
        } else {
            manager.addTodo(content: text, reminderDate: reminderEnabled ? reminderDate : nil)
        }
        onClose()
    }
}
