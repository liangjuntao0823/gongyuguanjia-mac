import SwiftUI
import SwiftData

// MARK: - 待办事项（SwiftData 模型版，与 iOS 版对应；数据由 DataManager 统一管理）

struct TodoViews: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var newTitle = ""

    private var items: [TodoItem] {
        manager.todos.filter { $0.isDeleted != true }
            .sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted && $1.isCompleted }
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdDate > $1.createdDate
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("待办事项")
                    .font(.system(size: 18, weight: .bold))
                Text("共 \(items.count) 条")
                    .font(.system(size: 14))
                    .foregroundColor(.themeText3)
                Spacer()
                Button("关闭") { onClose() }
                    .macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("输入待办内容…", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { add() }
                    Button("添加") { add() }
                        .macPrimaryButton()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .font(.system(size: 36))
                            .foregroundColor(.gray)
                        Text("暂无待办")
                            .font(.system(size: 15))
                            .foregroundColor(.themeText3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { item in
                            HStack(spacing: 10) {
                                Button {
                                    manager.toggleTodo(item)
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(item.isCompleted ? .themeAccent : .gray)
                                }
                                .buttonStyle(.plain)
                                Text(item.content)
                                    .font(.system(size: 15))
                                    .strikethrough(item.isCompleted)
                                    .foregroundColor(item.isCompleted ? .themeText3 : .themeText)
                                Spacer()
                                if let reminder = item.reminderDate {
                                    Text("⏰ \(reminder.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.themeText3)
                                }
                                Button {
                                    manager.softDeleteTodo(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.themeDanger)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .background(Color.themeBg)
        }
        .frame(width: 460, height: 480)
        .background(Color.themeBg)
    }

    private func add() {
        manager.addTodo(content: newTitle)
        newTitle = ""
    }
}
