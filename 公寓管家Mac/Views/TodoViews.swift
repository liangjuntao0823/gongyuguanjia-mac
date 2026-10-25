import SwiftUI
import SwiftData

// MARK: - 待办事项（轻量清单；与 iOS 版「待办」对应）

struct TodoItem: Identifiable {
    let id = UUID()
    var title: String
    var done: Bool
    var createdAt: Date
}

struct TodoViews: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var items: [TodoItem] = []
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("待办事项")
                    .font(.system(size: 17, weight: .bold))
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
                            .font(.system(size: 13))
                            .foregroundColor(.themeText3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach($items) { $item in
                            HStack(spacing: 10) {
                                Button {
                                    item.done.toggle()
                                    save()
                                } label: {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(item.done ? .themeAccent : .gray)
                                }
                                .buttonStyle(.plain)
                                Text(item.title)
                                    .font(.system(size: 13))
                                    .strikethrough(item.done)
                                    .foregroundColor(item.done ? .themeText3 : .themeText)
                                Spacer()
                                Button {
                                    items.removeAll { $0.id == item.id }
                                    save()
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
        .onAppear { load() }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        items.append(TodoItem(title: title, done: false, createdAt: Date()))
        newTitle = ""
        save()
    }

    private func save() {
        let data = items.map { ["id": $0.id.uuidString, "title": $0.title, "done": $0.done, "created": $0.createdAt.timeIntervalSince1970] }
        if let encoded = try? JSONSerialization.data(withJSONObject: data) {
            UserDefaults.standard.set(encoded, forKey: "todo.items.v1")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "todo.items.v1"),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        items = arr.compactMap { item in
            guard let title = item["title"] as? String else { return nil }
            let idStr = item["id"] as? String ?? UUID().uuidString
            return TodoItem(id: UUID(uuidString: idStr) ?? UUID(),
                            title: title,
                            done: item["done"] as? Bool ?? false,
                            createdAt: Date(timeIntervalSince1970: item["created"] as? Double ?? 0))
        }
    }
}
