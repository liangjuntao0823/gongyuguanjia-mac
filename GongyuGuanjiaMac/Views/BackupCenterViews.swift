import SwiftUI
import SwiftData

// MARK: - 备份中心（本地 + 云端备份历史、恢复、删除、自动备份开关）

struct BackupCenterViews: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var localItems: [(url: URL, date: Date, size: Int64, isFull: Bool)] = []
    @State private var cloudItems: [(name: String, size: Int64, date: Date)] = []
    @State private var autoBackup = CloudBackupService.autoBackupEnabled
    @State private var working = false
    @State private var message = ""
    @State private var confirmRestore: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("备份中心")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button("刷新") { refresh() }
                    .macSecondaryButton()
                Button("关闭") { onClose() }
                    .macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                // 自动备份
                HStack(spacing: 10) {
                    Toggle("自动备份（每 6 小时，备份后自动上传云端）", isOn: $autoBackup)
                        .onChange(of: autoBackup) { _, v in
                            CloudBackupService.autoBackupEnabled = v
                        }
                    Spacer()
                    Button("立即快速备份") {
                        quick()
                    }
                    .macPrimaryButton()
                    .disabled(working)
                    Button("立即全量备份") {
                        full()
                    }
                    .macSecondaryButton()
                    .disabled(working)
                }

                if working {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("处理中…").font(.system(size: 12))
                    }
                }
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(message.contains("失败") ? .themeDanger : .themeAccent)
                }

                // 本地备份
                VStack(alignment: .leading, spacing: 6) {
                    Text("本地备份（\(localItems.count)）")
                        .font(.system(size: 13, weight: .semibold))
                    if localItems.isEmpty {
                        Text("暂无本地备份").font(.system(size: 12)).foregroundColor(.themeText3)
                    } else {
                        List(localItems, id: \.url) { item in
                            HStack {
                                Text(item.url.lastPathComponent)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Text(FormatKit.dateTimeStr(item.date))
                                    .font(.system(size: 11))
                                    .foregroundColor(.themeText3)
                                Text(item.isFull ? "全量" : "快速")
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(item.isFull ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                                    .cornerRadius(4)
                                Text("\(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.themeText3)
                                Spacer()
                                Button("恢复") {
                                    confirmRestore = { restoreLocal(item.url) }
                                }
                                .macSecondaryButton()
                                Button("删除") {
                                    BackupV5Manager.deleteLocal(url: item.url)
                                    MacToastCenter.show("已删除本地备份")
                                    refresh()
                                }
                                .macSecondaryButton()
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(height: 150)
                    }
                }

                // 云端备份
                VStack(alignment: .leading, spacing: 6) {
                    Text("云端备份（\(cloudItems.count)）")
                        .font(.system(size: 13, weight: .semibold))
                    if cloudItems.isEmpty {
                        Text("暂无云端备份（配置云端后自动上传）").font(.system(size: 12)).foregroundColor(.themeText3)
                    } else {
                        List(cloudItems, id: \.name) { item in
                            HStack {
                                Text(item.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Text(FormatKit.dateTimeStr(item.date))
                                    .font(.system(size: 11))
                                    .foregroundColor(.themeText3)
                                Text("\(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.themeText3)
                                Spacer()
                                Button("下载并恢复") {
                                    guard let config = CosConfig.load() else {
                                        message = "失败：未配置云端"; return
                                    }
                                    confirmRestore = { restoreCloud(item.name, config: config) }
                                }
                                .macSecondaryButton()
                                Button("删除") {
                                    guard let config = CosConfig.load() else { return }
                                    Task {
                                        await BackupV5Manager.deleteCloud(name: item.name, config: config)
                                        MacToastCenter.show("已删除云端备份")
                                        refresh()
                                    }
                                }
                                .macSecondaryButton()
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(height: 150)
                    }
                }

                Spacer()
            }
            .padding(16)
        }
        .frame(width: 680, height: 620)
        .background(Color.themeBg)
        .onAppear { refresh() }
        .confirmationDialog("恢复备份会覆盖当前数据，确定继续？", isPresented: Binding(
            get: { confirmRestore != nil },
            set: { if !$0 { confirmRestore = nil } }
        ), titleVisibility: .visible) {
            Button("确定恢复", role: .destructive) {
                confirmRestore?()
                confirmRestore = nil
            }
            Button("取消", role: .cancel) { confirmRestore = nil }
        }
    }

    private func refresh() {
        localItems = BackupV5Manager.localBackups()
        guard let config = CosConfig.load() else {
            cloudItems = []
            return
        }
        Task {
            cloudItems = await BackupV5Manager.cloudBackups(config: config)
        }
    }

    private func quick() {
        working = true
        message = ""
        Task {
            let r = await BackupV5Manager.runQuickBackup(mainContext: manager.mainContext,
                                                         houseContext: manager.houseContext,
                                                         uploadCloud: CosConfig.load() != nil)
            switch r {
            case .success: message = "✓ 快速备份完成"
            case .failure(let e): message = "备份失败：\(e)"
            }
            working = false
            refresh()
        }
    }

    private func full() {
        working = true
        message = ""
        Task {
            let r = await BackupV5Manager.runFullBackup(mainContext: manager.mainContext,
                                                        houseContext: manager.houseContext,
                                                        uploadCloud: CosConfig.load() != nil)
            switch r {
            case .success: message = "✓ 全量备份完成"
            case .failure(let e): message = "备份失败：\(e)"
            }
            working = false
            refresh()
        }
    }

    private func restoreLocal(_ url: URL) {
        working = true
        message = ""
        Task {
            let r = await BackupV5Manager.restoreLocal(url: url, mainContext: manager.mainContext, houseContext: manager.houseContext)
            switch r {
            case .success:
                message = "✓ 恢复完成"
                NotificationCenter.default.post(name: .macHouseChanged, object: nil)
                NotificationCenter.default.post(name: .macDataChanged, object: nil)
            case .failure(let e): message = "恢复失败：\(e)"
            }
            working = false
        }
    }

    private func restoreCloud(_ name: String, config: CosConfig) {
        working = true
        message = ""
        Task {
            let r = await BackupV5Manager.restoreCloud(name: name, config: config, mainContext: manager.mainContext, houseContext: manager.houseContext)
            switch r {
            case .success:
                message = "✓ 云端备份恢复完成"
                NotificationCenter.default.post(name: .macHouseChanged, object: nil)
                NotificationCenter.default.post(name: .macDataChanged, object: nil)
            case .failure(let e): message = "恢复失败：\(e)"
            }
            working = false
        }
    }
}
