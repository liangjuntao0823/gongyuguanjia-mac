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
    @State private var showLogs = false
    @State private var showVersionHistory = false
    @State private var showInterconnection = false
    @State private var showManualSync = false
    @State private var showClearSheet = false
    @State private var clearConfirm = false
    @State private var clearMessage = ""
    @State private var syncing = false
    @State private var syncMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.system(size: 19, weight: .bold))
                Spacer()
                if syncing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("同步中…").font(.system(size: 12))
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
                            Text(syncMessage).font(.system(size: 12))
                                .foregroundColor(syncMessage.contains("✓") ? .themeAccent : .themeDanger)
                        }
                        Text("与 iOS 版共用同一云端：房源/媒体/分享页互通。用户名决定私有数据隔离。")
                            .font(.system(size: 11)).foregroundColor(.themeText3)
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
                            .font(.system(size: 11)).foregroundColor(.themeText3)
                    }

                    // 数据管理
                    section("数据管理") {
                        HStack(spacing: 10) {
                            Button("回收站") { showTrash = true }.macSecondaryButton()
                            Button("工具（导入导出/日志/缓存）") { showUtility = true }.macSecondaryButton()
                            Button("清空数据") { showClearSheet = true }.macSecondaryButton()
                            Spacer()
                        }
                        if !clearMessage.isEmpty {
                            Text(clearMessage).font(.system(size: 12)).foregroundColor(.themeText3)
                        }
                    }

                    // 日志与历史
                    section("日志与历史") {
                        HStack(spacing: 10) {
                            Button("崩溃/操作日志") { showLogs = true }.macSecondaryButton()
                            Button("手动同步/迁移") { showManualSync = true }.macSecondaryButton()
                            Button("版本更新介绍") { showVersionHistory = true }.macSecondaryButton()
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
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("公寓管家 Mac 版").font(.system(size: 14, weight: .semibold))
                                Text("版本 \(MacBridge.appVersion)（构建 \(MacBridge.appBuild)）")
                                    .font(.system(size: 12)).foregroundColor(.themeText2)
                                Text("数据存储：\(DataRoot.directory.path)")
                                    .font(.system(size: 11)).foregroundColor(.themeText3).lineLimit(1)
                            }
                            Spacer()
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
        .sheet(isPresented: $showUtility) { UtilityView(manager: manager) { showUtility = false } }
        .sheet(isPresented: $showUserGuide) { UserGuideView(manager: manager) { showUserGuide = false } }
        .sheet(isPresented: $showLogs) {
            VStack(spacing: 0) {
                HStack {
                    Text("崩溃/操作日志").font(.system(size: 16, weight: .bold))
                    Spacer()
                    Button("导出") { exportLogs() }.macSecondaryButton()
                    Button("清空") {
                        CrashLogCollector.clear()
                        MacToastCenter.show("日志已清空")
                    }.macSecondaryButton()
                    Button("关闭") { showLogs = false }.macPrimaryButton()
                }
                .padding(14)
                Divider()
                ScrollView {
                    Text(CrashLogCollector.logsText().isEmpty ? "暂无日志" : CrashLogCollector.logsText())
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
            }
            .frame(width: 560, height: 440)
        }
        .sheet(isPresented: $showVersionHistory) { VersionHistoryView { showVersionHistory = false } }
        .sheet(isPresented: $showInterconnection) { InterconnectionInfoView { showInterconnection = false } }
        .sheet(isPresented: $showManualSync) { ManualSyncView(manager: manager) { showManualSync = false } }
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
            Text(title).font(.system(size: 14, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
    }

    // MARK: - 动作

    private func pull() {
        guard CosConfig.load() != nil else { syncMessage = "未配置云端"; return }
        syncing = true
        syncMessage = "正在从云端拉取…"
        Task {
            let result = await manager.syncFromCloud()
            switch result {
            case .success(let added, let updated, _):
                syncMessage = "✓ 同步完成：新增 \(added) 套、更新 \(updated) 套（媒体已自动补齐）"
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
            case .success(let pushed, _, _):
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
                Text("版本更新介绍").font(.system(size: 16, weight: .bold))
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
                                Text(v.0).font(.system(size: 15, weight: .bold))
                                Text(v.1).font(.system(size: 12)).foregroundColor(.themeText3)
                            }
                            ForEach(v.2, id: \.self) { line in
                                Text("• \(line)").font(.system(size: 12)).foregroundColor(.themeText2)
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
                Text("三端互通说明").font(.system(size: 16, weight: .bold))
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
            Text(title).font(.system(size: 13, weight: .bold))
            Text(desc).font(.system(size: 12)).foregroundColor(.themeText2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorder))
    }
}
