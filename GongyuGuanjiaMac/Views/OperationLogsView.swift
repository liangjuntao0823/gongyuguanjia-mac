import SwiftUI

// MARK: - 操作日志（本机操作 + 云端操作，对齐 iOS v1.20/v1.63）

struct OperationLogsView: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var segment = 0           // 0 本机操作 / 1 云端操作
    @State private var searchText = ""
    @State private var cloudEntries: [CloudOpEntry] = []
    @State private var cloudLoaded = false
    @State private var cloudError: String?
    @State private var cloudSelection: Set<CloudOpEntry> = []
    @State private var editingCloud = false

    /// 失败词表（统一显示规则：命中即标红）
    private let failWords = ["失败", "错误", "异常", "无法", "不可用", "无效", "超时", "拒绝"]

    private var localEntries: [BackupLogEntry] {
        let all = BackupLogStore.load()
        if searchText.isEmpty { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.detail.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredCloud: [CloudOpEntry] {
        let list = cloudEntries
        if searchText.isEmpty { return list }
        return list.filter {
            $0.op.localizedCaseInsensitiveContains(searchText) ||
            $0.room.localizedCaseInsensitiveContains(searchText) ||
            $0.user.localizedCaseInsensitiveContains(searchText) ||
            $0.detail.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Text("操作日志").font(.system(size: 17, weight: .bold))
                Picker("", selection: $segment) {
                    Text("本机操作").tag(0)
                    Text("云端操作").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
                if segment == 1 {
                    Button {
                        editingCloud.toggle()
                        if !editingCloud { cloudSelection.removeAll() }
                    } label: {
                        Label(editingCloud ? "完成" : "多选", systemImage: editingCloud ? "checkmark" : "checkmark.circle")
                    }
                    .macSecondaryButton()
                    if editingCloud && !cloudSelection.isEmpty {
                        Button {
                            deleteSelectedCloud()
                        } label: { Label("删除所选(\(cloudSelection.count))", systemImage: "trash") }
                        .macSecondaryButton()
                    }
                    Button { loadCloud() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                        .macSecondaryButton()
                } else {
                    Button("清空") {
                        BackupLogStore.clear()
                        MacToastCenter.show("操作日志已清空")
                    }.macSecondaryButton()
                }
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)

            // 搜索
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.themeText3)
                TextField("搜索日志内容…", text: $searchText).textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            if segment == 0 {
                localList
            } else {
                cloudList
            }
        }
        .frame(width: 640, height: 480)
        .onAppear { if segment == 1 { loadCloud() } }
        .onChange(of: segment) { _, seg in if seg == 1 { loadCloud() } }
    }

    // MARK: 本机操作
    private var localList: some View {
        ScrollView {
            let entries = localEntries
            if entries.isEmpty {
                Text("暂无操作日志").font(.system(size: 14, weight: .medium)).foregroundColor(.themeText2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(e.kind.uppercased())] \(e.title)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isFail(e.title + " " + e.detail) ? .themeDanger : .themeText)
                            Text("\(e.time.formatted(date: .abbreviated, time: .shortened)) · \(e.detail)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isFail(e.detail) ? .themeDanger : .themeText2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: 云端操作
    private var cloudList: some View {
        Group {
            if let err = cloudError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 30, weight: .medium)).foregroundColor(.themeDanger)
                    Text(err).font(.system(size: 13, weight: .medium)).foregroundColor(.themeDanger)
                    Button("重试") { loadCloud() }.macSecondaryButton()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCloud.isEmpty {
                Text(cloudLoaded ? "暂无云端操作记录" : "加载云端操作记录…")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(.themeText2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredCloud) { e in
                            HStack(spacing: 10) {
                                if editingCloud {
                                    Image(systemName: cloudSelection.contains(e) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(cloudSelection.contains(e) ? .accentColor : .gray)
                                        .onTapGesture {
                                            if cloudSelection.contains(e) { cloudSelection.remove(e) }
                                            else { cloudSelection.insert(e) }
                                        }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(e.op)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(isFail(e.op + " " + e.detail) ? .themeDanger : .themeText)
                                        Text("👤 \(e.user)")
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.12))
                                            .clipShape(Capsule())
                                        Spacer()
                                        Text(e.t).font(.system(size: 11, weight: .medium)).foregroundColor(.themeText2)
                                    }
                                    if !e.room.isEmpty {
                                        Text("房号：\(e.room)").font(.system(size: 11, weight: .medium)).foregroundColor(.themeText2)
                                    }
                                    if !e.detail.isEmpty {
                                        Text(e.detail)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(isFail(e.detail) ? .themeDanger : .themeText2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(12)
                }
                .textSelection(.enabled)
            }
        }
    }

    private func isFail(_ text: String) -> Bool {
        failWords.contains { text.contains($0) }
    }

    private func loadCloud() {
        cloudError = nil
        cloudLoaded = false
        CloudOps.fetch { list in
            DispatchQueue.main.async {
                cloudEntries = list
                cloudLoaded = true
                if editingCloud {
                    cloudSelection = cloudSelection.filter { list.contains($0) }
                }
            }
        }
    }

    private func deleteSelectedCloud() {
        let items = Array(cloudSelection)
        guard !items.isEmpty else { return }
        let group = DispatchGroup()
        for e in items {
            group.enter()
            CloudOps.delete(e) { group.leave() }
        }
        group.notify(queue: .main) {
            MacToastCenter.show("已删除 \(items.count) 条云端日志")
            cloudSelection.removeAll()
            loadCloud()
        }
    }
}
