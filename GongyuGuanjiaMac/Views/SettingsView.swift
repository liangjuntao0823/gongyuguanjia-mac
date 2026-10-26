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
        .sheet(isPresented: $showOpLogs) {
            VStack(spacing: 0) {
                HStack {
                    Text("操作日志").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Button("清空") {
                        BackupLogStore.clear()
                        MacToastCenter.show("操作日志已清空")
                    }.macSecondaryButton()
                    Button("关闭") { showOpLogs = false }.macPrimaryButton()
                }
                .padding(14)
                Divider()
                ScrollView {
                    let entries = BackupLogStore.load()
                    if entries.isEmpty {
                        Text("暂无操作日志").font(.system(size: 14)).foregroundColor(.themeText2)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(entries) { e in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("[\(e.kind.uppercased())] \(e.title)")
                                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.themeText)
                                    Text("\(e.time.formatted(date: .abbreviated, time: .shortened)) · \(e.detail)")
                                        .font(.system(size: 12)).foregroundColor(.themeText2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(width: 560, height: 440)
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
        ("v1.2.1", "2026-10-27", [
            "修复收租/包租板块排版：卡片恢复桌面端全宽横排（上一版误改为窄网格导致信息挤压错乱）",
            "包租/收租卡片操作按钮改为横排（详情/编辑/删除），符合 Mac 桌面操作习惯",
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
