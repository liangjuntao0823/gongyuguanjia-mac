import SwiftUI
import SwiftData

// MARK: - 设置（对齐 iOS：云同步 / 备份 / 数据管理(清空) / 分享配置 / 日志 / 版本历史 / 说明）

struct SettingsView: View {
    @ObservedObject var manager: DataManager

    @State private var showShareSettings = false
    @State private var showBackupCenter = false
    @State private var showTrash = false
    @State private var showUtility = false
    @State private var showUserGuide = false
    @State private var showCrashLogs = false
    @State private var showOpLogs = false
    @State private var showVersionHistory = false
    @State private var pendingPullDetail = ""
    @State private var showPullConfirm = false
    @State private var showInterconnection = false
    @State private var showManualSync = false
    @State private var showRemoteConfig = false
    @State private var notifyEnabled = LocalNotificationManager.isEnabled
    @State private var notifyAdvanceDays = "3"
    @State private var rentNotifyOn = LocalNotificationManager.categoryEnabled("rent")
    @State private var expiryNotifyOn = LocalNotificationManager.categoryEnabled("expiry")
    @State private var payoutNotifyOn = LocalNotificationManager.categoryEnabled("payout")
    @State private var todoNotifyOn = LocalNotificationManager.categoryEnabled("todo")
    @State private var showClearSheet = false
    @State private var clearConfirm = false
    @State private var clearMessage = ""
    @State private var syncing = false
    @State private var syncMessage = ""

    // MARK: 自动备份配置（与 iOS 同 key）
    @AppStorage("backup.autoEnabled") private var autoBackupEnabled = true
    @AppStorage("autoBackupFrequency") private var autoBackupFrequency = "daily"   // daily/weekly/monthly
    @AppStorage("autoBackupRetentionDays") private var autoBackupRetentionDays = 7
    @State private var showBackupConfig = false

    // MARK: 水电默认值（与 iOS 同 key，UtilityView 实时读取）
    @AppStorage("defaultElectricPrice") private var defaultElectricPrice = "0.8"
    @AppStorage("defaultWaterPrice") private var defaultWaterPrice = "5.5"
    @AppStorage("defaultUtilityPrepayment") private var defaultUtilityPrepayment = "0"

    // MARK: 账单模板 / 待补传媒体
    @State private var showBillTemplate = false
    @State private var showMediaPending = false
    @State private var migrating = false
    @State private var migratedTip = "旧版 1 座媒体目录无前缀，需迁移为 1- 前缀与 iOS 对齐"


    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.system(size: 20, weight: .bold))
                Spacer()
                if syncing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("同步中…").font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 云端同步
                    section("云端同步") {
                        HStack(spacing: 10) {
                            Button("从云端拉取") { pull() }.macPrimaryButton().disabled(syncing)
                            Button("推送本机到云端") { push() }.macSecondaryButton().disabled(syncing)
                            Button("云端/分享设置") { showShareSettings = true }.macSecondaryButton()
                            Spacer()
                        }
                        if !syncMessage.isEmpty {
                            Text(syncMessage).font(.system(size: 14))
                                .foregroundColor(syncMessage.contains("✓") ? .themeAccent : .themeDanger)
                        }
                        Text("与 iOS 版共用同一云端：房源/媒体/分享页互通。用户名决定私有数据隔离。")
                            .font(.system(size: 13)).foregroundColor(.themeText3)
                    }

                    // 备份与恢复
                    section("备份与恢复") {
                        HStack(spacing: 10) {
                            Button("打开备份中心") { showBackupCenter = true }.macPrimaryButton()
                            Button("立即快速备份") { quickBackup() }.macSecondaryButton()
                            Button("立即全量备份") { fullBackup() }.macSecondaryButton()
                            Spacer()
                        }
                        Text("快速备份含经营数据+房源字段；全量备份另含实拍媒体。可自动上传云端。")
                            .font(.system(size: 13)).foregroundColor(.themeText3)
                    }

                    // 数据管理
                    section("数据管理") {
                        HStack(spacing: 10) {
                            Button("回收站") { showTrash = true }.macSecondaryButton()
                            Button("水电结算") { showUtility = true }.macSecondaryButton()
                            Button("清空数据") { showClearSheet = true }.macSecondaryButton()
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Button("离线重建房源") { rebuildFromLocalLedger() }.macSecondaryButton()
                            Text("从本地账本镜像（media/<房号>/info.json）重建/补齐房源，无需联网")
                                .font(.system(size: 13)).foregroundColor(.themeText3)
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Text("数据文件夹：\(DataRoot.directory.path)")
                                .font(.system(size: 13)).foregroundColor(.themeText3).lineLimit(1)
                            Spacer()
                            Button("打开") { openDataFolder() }.macSecondaryButton()
                        }
                        // P0-2 一次性迁移：1 座媒体目录补前缀（media/2334上 → media/1-2334上）
                        HStack(spacing: 10) {
                            Text(migratedTip)
                                .font(.system(size: 13)).foregroundColor(.themeText3).lineLimit(1)
                            Spacer()
                            Button(migrating ? "迁移中…" : "迁移 1 座媒体目录") { migrateTower1Media() }
                                .macSecondaryButton()
                                .disabled(migrating)
                        }
                        HStack(spacing: 10) {
                            Text("已收录房源：\(manager.houses.count) 套 · 文件夹大小：\(folderSizeText)")
                                .font(.system(size: 13)).foregroundColor(.themeText3)
                            Spacer()
                        }
                        if !clearMessage.isEmpty {
                            Text(clearMessage).font(.system(size: 14)).foregroundColor(.themeText3)
                        }
                    }

                    // 自动备份
                    section("自动备份") {
                        Toggle("启用自动备份（备份成功后自动上传云端）", isOn: $autoBackupEnabled)
                            .onChange(of: autoBackupEnabled) { _, v in CloudBackupService.autoBackupEnabled = v }
                        HStack(spacing: 10) {
                            Text("频率").font(.system(size: 15)).foregroundColor(.themeText2)
                            Picker("", selection: $autoBackupFrequency) {
                                Text("每天").tag("daily")
                                Text("每周").tag("weekly")
                                Text("每月").tag("monthly")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                            Spacer()
                            Text("保留").font(.system(size: 15)).foregroundColor(.themeText2)
                            Stepper("\(autoBackupRetentionDays) 天", value: $autoBackupRetentionDays, in: 1...30)
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Button("立即快速备份") { quickBackup() }.macSecondaryButton()
                            Button("打开备份中心") { showBackupCenter = true }.macSecondaryButton()
                            Spacer()
                        }
                        Text("自动备份 = 快速备份（账本 + 房源 + 清单），超过保留天数的自动备份会自动清理，手动备份不会被删除。")
                            .font(.system(size: 13)).foregroundColor(.themeText3)
                    }

                    // 水电默认值
                    section("水电默认值") {
                        HStack(spacing: 10) {
                            Text("电费单价").font(.system(size: 15)).foregroundColor(.themeText2)
                            TextField("0.8", text: $defaultElectricPrice)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Spacer()
                            Text("水费单价").font(.system(size: 15)).foregroundColor(.themeText2)
                            TextField("5.5", text: $defaultWaterPrice)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Spacer()
                            Text("默认总预存").font(.system(size: 15)).foregroundColor(.themeText2)
                            TextField("0", text: $defaultUtilityPrepayment)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                        Text("默认单价和预存仅用于新增房源，不影响已生成的结算记录。")
                            .font(.system(size: 13)).foregroundColor(.themeText3)
                    }

                    // 账单模板
                    section("账单模板") {
                        HStack(spacing: 10) {
                            Button("账单模板设置（固定文本/收款码/预览）") { showBillTemplate = true }.macSecondaryButton()
                            Spacer()
                        }
                        Text("用于收租详情的「分享收租账单」，文本与收款码实时生效。")
                            .font(.system(size: 13)).foregroundColor(.themeText3)
                    }


                    // 提醒设置（对齐 iOS：四类提醒可配置；Mac 通知使用系统默认音）
                    section("提醒设置") {
                        HStack(spacing: 10) {
                            Toggle("启用提醒", isOn: $notifyEnabled)
                                .onChange(of: notifyEnabled) { _, v in LocalNotificationManager.isEnabled = v }
                            Spacer()
                            Text("提前提醒天数").font(.system(size: 14)).foregroundColor(.themeText2)
                            TextField("3", text: $notifyAdvanceDays)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .onChange(of: notifyAdvanceDays) { _, v in
                                    let d = Int(v.trimmingCharacters(in: .whitespaces)) ?? 3
                                    LocalNotificationManager.advanceDays = max(0, min(d, 30))
                                }
                        }
                        HStack(spacing: 10) {
                            Toggle("收租提醒", isOn: $rentNotifyOn)
                                .onChange(of: rentNotifyOn) { _, v in UserDefaults.standard.set(v, forKey: "notify.rent.enabled") }
                            Toggle("租期到期提醒", isOn: $expiryNotifyOn)
                                .onChange(of: expiryNotifyOn) { _, v in UserDefaults.standard.set(v, forKey: "notify.expiry.enabled") }
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Toggle("包租付租提醒", isOn: $payoutNotifyOn)
                                .onChange(of: payoutNotifyOn) { _, v in UserDefaults.standard.set(v, forKey: "notify.payout.enabled") }
                            Toggle("待办提醒", isOn: $todoNotifyOn)
                                .onChange(of: todoNotifyOn) { _, v in UserDefaults.standard.set(v, forKey: "notify.todo.enabled") }
                            Spacer()
                        }
                        Text("macOS 通知使用系统默认音；提前天数对收租/到期提醒生效。")
                            .font(.system(size: 13)).foregroundColor(.themeText3)
                    }

                    // 远程配置中心（对齐 iOS v1.80-1.82）
                    section("远程配置") {
                        HStack(spacing: 10) {
                            Button("远程配置管理（公告/开关/参数/更新日志）") { showRemoteConfig = true }.macSecondaryButton()
                            Spacer()
                            Text(RemoteConfig.summary)
                                .font(.system(size: 13)).foregroundColor(.themeText3)
                        }
                        if let ann = RemoteConfig.announcement, ann.enabled, !ann.text.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "megaphone").foregroundColor(.orange)
                                Text("公告：\(ann.text)").font(.system(size: 13)).foregroundColor(.themeText2)
                                if let link = ann.link, let url = URL(string: link) {
                                    Link("查看", destination: url).font(.system(size: 13))
                                }
                                Spacer()
                            }
                        }
                        Text("云端 config.json 优先；断网读本地缓存；均无则用内置默认值。")
                            .font(.system(size: 13)).foregroundColor(.themeText3)
                    }

                    // 日志与历史
                    section("日志与历史") {
                        HStack(spacing: 10) {
                            Button("崩溃日志") { showCrashLogs = true }.macSecondaryButton()
                            Button("操作日志") { showOpLogs = true }.macSecondaryButton()
                            Button("手动同步/迁移") { showManualSync = true }.macSecondaryButton()
                            Button("三端互通说明") { showInterconnection = true }.macSecondaryButton()
                            Spacer()
                        }
                    }

                    // 其他
                    section("其他") {
                        HStack(spacing: 10) {
                            Button("使用说明") { showUserGuide = true }.macSecondaryButton()
                            Button("查看完整功能报告") { openReport() }.macSecondaryButton()
                            Spacer()
                        }
                    }

                    // 关于
                    section("关于") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("公寓管家 Mac 版").font(.system(size: 16, weight: .semibold))
                                    Text("版本 \(MacBridge.appVersion)（构建 \(MacBridge.appBuild)）")
                                        .font(.system(size: 14)).foregroundColor(.themeText2)
                                }
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                Text("开发者").font(.system(size: 15)).foregroundColor(.themeText2)
                                Text("梁涛").font(.system(size: 15)).foregroundColor(.themeText)
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                Text("软件说明").font(.system(size: 15)).foregroundColor(.themeText2)
                                Text("公寓管家 = 租房管家（经营）+ 房源管家（获客分享），与 iOS 版共用同一云端。")
                                    .font(.system(size: 14)).foregroundColor(.themeText).lineLimit(2)
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                Text("数据安全").font(.system(size: 15)).foregroundColor(.themeText2)
                                Text("数据存于本机「Application Support/公寓管家Mac」，云端仅在你配置后同步。")
                                    .font(.system(size: 14)).foregroundColor(.themeText).lineLimit(2)
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                Button("版本更新介绍") { showVersionHistory = true }.macSecondaryButton()
                                Button("三端互通说明") { showInterconnection = true }.macSecondaryButton()
                                Button("待补传媒体") { showMediaPending = true }.macSecondaryButton()
                                Spacer()
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showShareSettings) { HouseSettingsView(manager: manager) { showShareSettings = false } }
        .sheet(isPresented: $showBackupCenter) { BackupCenterViews(manager: manager) { showBackupCenter = false } }
        .sheet(isPresented: $showTrash) { TrashView(manager: manager) { showTrash = false } }
        .sheet(isPresented: $showUtility) { UtilityView(manager: manager, onClose: { showUtility = false }) }
        .sheet(isPresented: $showUserGuide) { UserGuideView(manager: manager) { showUserGuide = false } }
        .sheet(isPresented: $showCrashLogs) {
            VStack(spacing: 0) {
                HStack {
                    Text("崩溃日志").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Button("导出") { exportLogs() }.macSecondaryButton()
                    Button("清空") {
                        CrashLogCollector.clear()
                        MacToastCenter.show("日志已清空")
                    }.macSecondaryButton()
                    Button("关闭") { showCrashLogs = false }.macPrimaryButton()
                }
                .padding(14)
                Divider()
                ScrollView {
                    Text(CrashLogCollector.logsText().isEmpty ? "暂无崩溃日志" : CrashLogCollector.logsText())
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
            }
            .frame(width: 560, height: 440)
        }
        .sheet(isPresented: $showRemoteConfig) {
            RemoteConfigAdminView()
        }
        .sheet(isPresented: $showOpLogs) {
            OperationLogsView(manager: manager) { showOpLogs = false }
        }
        .sheet(isPresented: $showVersionHistory) { VersionHistoryView { showVersionHistory = false } }
        .sheet(isPresented: $showInterconnection) { InterconnectionInfoView { showInterconnection = false } }
        .sheet(isPresented: $showManualSync) { ManualSyncView(manager: manager) { showManualSync = false } }
        .sheet(isPresented: $showBillTemplate) { BillTemplateSettingsView { showBillTemplate = false } }
        .sheet(isPresented: $showMediaPending) { MediaPendingView { showMediaPending = false } }
        .alert("发现云端变化", isPresented: $showPullConfirm) {
            Button("应用变更") { applyPendingPull() }.macPrimaryButton()
            Button("取消", role: .cancel) { }
        } message: {
            Text(pendingPullDetail)
        }
        .confirmationDialog("清空数据将删除所选板块的全部记录（删除前请先备份）。",
                            isPresented: $showClearSheet, titleVisibility: .visible) {
            Button("清空成交数据", role: .destructive) { performClear(kind: .deals) }
            Button("清空收租数据", role: .destructive) { performClear(kind: .properties) }
            Button("清空包租数据", role: .destructive) { performClear(kind: .payouts) }
            Button("清空全部数据", role: .destructive) { performClear(kind: .total) }
            Button("取消", role: .cancel) { }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
    }


    // MARK: - 数据文件夹

    private var folderSizeText: String {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: DataRoot.directory,
                                                     includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                     options: [.skipsHiddenFiles]) else { return "0 KB" }
        var total: Int64 = 0
        for url in dirs {
            if let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               vals.isRegularFile == true {
                total += Int64(vals.fileSize ?? 0)
            }
        }
        if total >= 1_048_576 { return String(format: "%.1f MB", Double(total) / 1_048_576) }
        if total >= 1024 { return String(format: "%.0f KB", Double(total) / 1024) }
        return "\(total) B"
    }

    /// 离线重建房源：扫描本地账本镜像补齐/新建房源（对齐 iOS v1.75）
    private func rebuildFromLocalLedger() {
        let n = LocalHouseLedger.restoreAll(houseContext: manager.houseContext)
        MacToastCenter.show(n > 0 ? "离线重建完成：处理 \(n) 套房源" : "未找到本地账本镜像（先执行一次云端同步生成）")
    }

    private func openDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([DataRoot.directory])
        MacToastCenter.show("已在访达中打开数据文件夹")
    }

    /// P0-2 一次性迁移：media 下无前缀目录 → 1- 前缀（2- 已带前缀不动），文件重命名合并
    private func migrateTower1Media() {
        migrating = true
        let mediaDir = DataRoot.mediaDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: mediaDir.path) else {
            migratedTip = "media 目录不存在或无内容"
            migrating = false
            return
        }
        var moved = 0
        for name in names {
            if name.hasPrefix("1-") || name.hasPrefix("2-") { continue }  // 已带前缀
            let from = mediaDir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: from.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let to = mediaDir.appendingPathComponent("1-\(name)")
            if FileManager.default.fileExists(atPath: to.path) {
                // 合并：把文件复制进已有 1- 目录
                if let files = try? FileManager.default.contentsOfDirectory(atPath: from.path) {
                    for f in files {
                        let dest = to.appendingPathComponent(f)
                        if !FileManager.default.fileExists(atPath: dest.path) {
                            try? FileManager.default.moveItem(at: from.appendingPathComponent(f), to: dest)
                        }
                    }
                }
                try? FileManager.default.removeItem(at: from)
            } else {
                try? FileManager.default.moveItem(at: from, to: to)
            }
            moved += 1
        }
        migratedTip = moved > 0 ? "✓ 已迁移 \(moved) 个目录（media/xxx → media/1-xxx），迁移后请在云端同步里重新推送一次账本" : "无需迁移（所有目录均已带前缀）"
        migrating = false
        MacToastCenter.show(moved > 0 ? "已迁移 \(moved) 个 1 座媒体目录" : "无需迁移")
    }

    // MARK: - 动作

    private func pull() {
        guard CosConfig.load() != nil else { syncMessage = "未配置云端"; return }
        syncing = true
        syncMessage = "正在读取云端差异…"
        Task {
            // 先 dryRun 算差异（不写库），展示确认框后再应用（对齐 iOS v1.40/v1.64）
            let dry = await CloudHouseSync.pullAndMerge(houseContext: manager.houseContext, apply: false)
            switch dry {
            case .success(_, _, _, let detail):
                syncing = false
                pendingPullDetail = detail
                showPullConfirm = true
            case .failure(let msg):
                syncMessage = "同步失败：\(msg)"
                syncing = false
            }
        }
    }

    private func applyPendingPull() {
        syncing = true
        syncMessage = "正在应用云端变更…"
        Task {
            let result = await manager.syncFromCloud(progress: { p, msg in
                Task { @MainActor in
                    syncMessage = "\(msg)（\(Int(p * 100))%）"
                }
            })
            switch result {
            case .success(let added, let updated, let removed, _):
                syncMessage = "✓ 同步完成：新增 \(added) 套、更新 \(updated) 套、删除 \(removed) 套（媒体已自动补齐）"
            case .failure(let msg):
                syncMessage = "同步失败：\(msg)"
            }
            syncing = false
        }
    }

    private func push() {
        guard CosConfig.load() != nil else { syncMessage = "未配置云端"; return }
        syncing = true
        syncMessage = "正在推送…"
        Task {
            let result = await manager.pushToCloud()
            switch result {
            case .success(let pushed, _, _, _):
                syncMessage = "✓ 已推送 \(pushed) 套房源到云端账本"
            case .failure(let msg):
                syncMessage = "推送失败：\(msg)"
            }
            syncing = false
        }
    }

    private func quickBackup() {
        Task {
            let result = await BackupV5Manager.runQuickBackup(mainContext: manager.mainContext,
                                                              houseContext: manager.houseContext,
                                                              uploadCloud: CosConfig.load() != nil)
            switch result {
            case .success: MacToastCenter.show("快速备份完成")
            case .failure(let msg): MacToastCenter.show("备份失败：\(msg)")
            }
        }
    }

    private func fullBackup() {
        Task {
            let result = await BackupV5Manager.runFullBackup(mainContext: manager.mainContext,
                                                             houseContext: manager.houseContext,
                                                             uploadCloud: CosConfig.load() != nil)
            switch result {
            case .success: MacToastCenter.show("全量备份完成")
            case .failure(let msg): MacToastCenter.show("备份失败：\(msg)")
            }
        }
    }

    private func performClear(kind: ClearKind) {
        var count = 0
        switch kind {
        case .deals:
            count = manager.deals.count
            for d in manager.deals { manager.mainContext.delete(d) }
        case .properties:
            count = manager.properties.count
            for p in manager.properties { manager.mainContext.delete(p) }
        case .payouts:
            count = manager.payouts.count
            for p in manager.payouts { manager.mainContext.delete(p) }
        case .total:
            count = manager.deals.count + manager.properties.count + manager.payouts.count +
                    manager.miscIncomes.count + manager.miscExpenses.count + manager.todos.count + manager.houses.count
            for d in manager.deals { manager.mainContext.delete(d) }
            for p in manager.properties { manager.mainContext.delete(p) }
            for p in manager.payouts { manager.mainContext.delete(p) }
            for i in manager.miscIncomes { manager.mainContext.delete(i) }
            for e in manager.miscExpenses { manager.mainContext.delete(e) }
            for t in manager.todos { manager.mainContext.delete(t) }
            for h in manager.houses { manager.permanentDeleteHouse(h) }
        }
        try? manager.mainContext.save()
        NotificationCenter.default.post(name: .macDataChanged, object: nil)
        clearMessage = "已清空 \(count) 条记录（建议尽快做一次备份）"
        MacToastCenter.show("已清空")
    }

    private func exportLogs() {
        MacBridge.saveFile(defaultName: "公寓管家日志_\(BackupTimestamp.string()).txt", allowedTypes: [.plainText]) { url in
            guard let url = url else { return }
            try? CrashLogCollector.logsText().write(to: url, atomically: true, encoding: .utf8)
            MacToastCenter.show("日志已导出")
        }
    }

    private func openReport() {
        MacBridge.openURL("https://aka.doubaocdn.com/s/BM7BmY6Tab")
    }
}

enum ClearKind {
    case deals, properties, payouts, total
}

// MARK: - 版本更新介绍（Mac 版各版本记录）

struct VersionHistoryView: View {
    let onClose: () -> Void
    private let versions: [(String, String, [String])] = [
        ("v1.2.9", "2026-10-28", [
            "同步性能：fetchAll 改为 delimiter 目录式列出（只列房号目录，不列媒体文件，省流量/加快列表）+ withThrowingTaskGroup 并发拉取各套账本（对齐 iOS）",
            "删除死代码 CloudHouseLedger（旧 h/_houses.json 单文件账本 + ISO8601 编码，零调用点），杜绝未来误写出旧格式",
            "全局同步进度悬浮条：同步/补传任务在任意页面右下角可见，可最小化收起（对齐 iOS 根级全局悬浮；房源页内嵌进度条保留）",
        ]),
        ("v1.2.8", "2026-10-27", [
            "租金字段类型统一为整数（iOS 同为 Int）：房源编辑/导入/同步/备份全链路对齐，Mac 录入非整数租金会四舍五入，两端同步不再丢小数",
        ]),
        ("v1.2.7", "2026-10-27", [
            "远程配置中心：云端 config.json 三级兜底（云端→本地缓存→内置默认），启动/同步后自动拉取；设置-远程配置管理可编辑公告/最低版本/功能开关/数值参数/提示文案/云端更新日志并发布（云函数 configGet/configSave）",
            "全局同步任务中心：同步/补传进度全局登记，房源页顶部可最小化收起，待补传媒体页顶部显示进行中任务卡片",
            "提醒设置：设置页新增四类提醒独立开关（收租/租期到期/包租付租/待办）+ 总开关 + 提前提醒天数（macOS 使用系统默认音）",
            "云端运营项：设置页新增刷新网页后台缓存（版本戳）、云端部署图文教程、配置备份到文件/从备份文件恢复、开通步骤简述",
            "启动自动迁移无前缀媒体目录（对齐 iOS：1 座/2 座目录统一带前缀）",
        ]),
        ("v1.2.6", "2026-10-27", [
            "本地账本镜像：每套房在 media/<房号>/info.json 同步一份（新增/编辑/媒体增删/删除/云端同步后自动维护）",
            "离线重建房源：设置-数据管理新增入口，扫描本地账本镜像一键重建/补齐房源，无需联网",
            "房源页本地刷新：媒体补全检测（磁盘有记录无→补建；记录有磁盘无→提示云端回补；孤儿目录提示扫描补录）",
            "云端同步顶部进度条：干跑检查与确认同步均显示进度",
            "批量恢复后界面自动刷新并重建本地账本镜像",
        ]),
        ("v1.2.5", "2026-10-27", [
            "待办板块补全：搜索、未办/已办筛选、新增/编辑/预览表单、提醒时间、拖拽排序、完成/删除确认、恢复未办理、提醒本地通知",
            "成交/包租/收租：新增「导出图片」（表格渲染 PNG 保存）、成交/包租「导出 Excel 模板」；成交增加年/月筛选与定位高亮",
            "汇总板块：新增年/月筛选（按所选年月统计卡片与月度明细）",
            "水电计划编辑器对齐 iOS：结算日期选择、按结算频率(月/季)推导期数、结算单备注、结算时间/到期日写入",
            "同步增强：媒体对账改为先查云端对象——对象在补账本、对象缺有本地文件自动补传、两者皆无才删除，避免误删",
            "设置页新增「分享记录（选房链接访问统计）」：云端 do_shares 按用户名展示房号/模式/时间/复制链接",
            "操作日志重做：本机/云端分区、云端多选删除、失败词标红、搜索框"
        ]),
        ("v1.2.4", "2026-10-27", [
            "房源删除云端联动：删除（进回收站）即同步删除云端账本（iOS 端同步消失），彻底删除=本地媒体+记录+云端桶目录全部对象+账本+分享页一并清除",
            "新增/编辑房源后自动推送单套账本（对齐 iOS uploadOne），不再依赖手动同步",
            "同步机制对齐 iOS：更新判定从时间戳改为字段级对比（cloudRecordDiffers）；媒体双向对账（云端缺本地→下载、本地有云端无→跟随删除、磁盘孤儿→清理）",
            "收租/包租卡片修复：交租日徽标已收月份改为深绿底白字（此前浅绿底白字在白卡片上看不见）；交租日 0 值兜底显示 1 号；卡片补齐经营类型（管理/包租/托管）徽标；信息区改为三栏/四栏网格，桌面大屏不再显空",
            "只改 Mac 项目，未触碰 iOS 工程与云端配置",
        ]),
        ("v1.2.3", "2026-10-27", [
            "收租/包租/退租卡片重新设计：改为桌面端多列网格卡片（宽屏一行多个），信息分组清晰、按钮横排完整显示",
            "修复同步：账本日期编码与 iOS 完全一致（iOS 读不了 ISO8601 字符串时间戳）；账本房号字段与 iOS 一致（无前缀本体，前缀只进目录名）；拉取跳过系统保留目录",
            "只改 Mac 项目，未触碰 iOS 工程与云端配置",
        ]),
        ("v1.2.2", "2026-10-27", [
            "云端配置改为本地存储：不再读写系统钥匙串，彻底解决未签名版本触发钥匙串授权弹窗（登录密码不对时无法放行）的问题",
            "注意：升级后需在设置 → 云端配置 重新填写一次 COS 配置（可在 iOS 端设置里照抄同一份）",
        ]),
        ("v1.2.1", "2026-10-27", [
            "修复收租/包租板块排版：卡片恢复桌面端全宽横排（上一版误改为窄网格导致信息挤压错乱）",
            "包租/收租卡片操作按钮改为横排（详情/编辑/删除），符合 Mac 桌面操作习惯",
            "修复同步不到房源：云端账本对齐 iOS v1.71 一房一文件机制（h/<房号>/info.json），废弃旧 _houses.json 汇总文件",
        ]),
        ("v1.2", "2026-10-27", [
            "房源数据字段与 iOS 完全对齐（房号前缀 1-/2-、photoSummary 有/无实拍图、lastUpdatedAt），双向同步互通",
            "批量导入三入口：CSV 清单 / zip 媒体包 / 扫描 media 补录，无前缀房号标红跳过",
            "房源列表多选：批量已租 / 批量删除 / 合集分享（N 套生成一个合集 H5）",
            "编辑房源页媒体管理：删旧传新一次保存；房号前缀强制 + 实时查重",
            "同步体验：列表刷新同步按钮（差异预览后确认）、同步进度百分比、云端删除跟随",
            "手动同步补「本机同步码」二维码（供 iOS 扫码）与 zfgj 链接复制",
            "工作台按桌面端重排（快捷操作一行、KPI 三列），全板块排版与全局字体调大",
            "设置页：移除自定义提示音、崩溃/操作日志分开、版本更新介绍只保留一处",
            "账单模板预览补支付宝/微信收款码；自动备份频率与备份中心口径统一",
            "数据管理增加「迁移 1 座媒体目录」（media/xxx → media/1-xxx，与 iOS 对齐）",
            "头像可点击更换；Logo 按 iOS 版重设计并适配 macOS 圆角图标",
        ]),
        ("v1.1", "2026-10-26", [
            "功能补齐：工作台对齐 iOS、设置页 9 大分组、全局字体调大",
            "修复 macOS 14/15 打开与稳定性问题",
        ]),
        ("v1.0", "2026-10-25", [
            "Mac 版首发：参照 iOS「公寓管家」功能全面重建（非移植）",
            "经营板块：工作台/收租/成交/包租/汇总/水电结算/待办/回收站",
            "房源板块：房源管理/详情/编辑/媒体实拍/选房链接/单房分享 H5",
            "云端：COS 配置/云端同步/快速与全量备份/分享缓存",
            "通用二进制（Intel + Apple Silicon），支持 macOS 14+",
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("版本更新介绍").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(versions.enumerated()), id: \.offset) { _, v in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(v.0).font(.system(size: 16, weight: .bold))
                                Text(v.1).font(.system(size: 14)).foregroundColor(.themeText3)
                            }
                            ForEach(v.2, id: \.self) { line in
                                Text("• \(line)").font(.system(size: 14)).foregroundColor(.themeText2)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.themePanel)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorder))
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - 三端互通说明

struct InterconnectionInfoView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("三端互通说明").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow("iOS / Mac 共用云端", "房源、实拍媒体、分享页全部走同一套 COS 存储与云函数，两端实时互通。")
                    infoRow("用户名隔离", "云端按用户名分区：同一用户名下数据互通，不同用户名互不可见。")
                    infoRow("选房链接", "本机生成选房 H5 上传云端，租客扫码/点链接即可浏览在租房源。")
                    infoRow("备份", "快速备份含经营数据+房源字段；全量备份含照片视频；可自动上传云端。")
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 420)
    }
    private func infoRow(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .bold))
            Text(desc).font(.system(size: 14)).foregroundColor(.themeText2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorder))
    }
}
