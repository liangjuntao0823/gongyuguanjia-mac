import SwiftUI
import SwiftData

// MARK: - 设置（云同步 / 备份中心 / 房源分享设置 / 工具 / 版本介绍 / 使用说明）

struct SettingsView: View {
    @ObservedObject var manager: DataManager
    @Environment(\.houseModelContext) private var houseContext

    @State private var showShareSettings = false
    @State private var showBackupCenter = false
    @State private var showTrash = false
    @State private var showUtility = false
    @State private var showUserGuide = false
    @State private var syncing = false
    @State private var syncMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                if syncing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("同步中…").font(.system(size: 12))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 云端同步
                    section("云端同步") {
                        HStack(spacing: 10) {
                            Button("从云端拉取") { pull() }
                                .macPrimaryButton()
                                .disabled(syncing)
                            Button("推送本机到云端") { push() }
                                .macSecondaryButton()
                                .disabled(syncing)
                            Button("打开房源分享设置") { showShareSettings = true }
                                .macSecondaryButton()
                            Spacer()
                        }
                        if !syncMessage.isEmpty {
                            Text(syncMessage)
                                .font(.system(size: 12))
                                .foregroundColor(syncMessage.contains("✓") ? .themeAccent : .themeDanger)
                        }
                        Text("与 iOS 版共用同一云端：房源/媒体/分享页互通。用户名决定私有数据隔离。")
                            .font(.system(size: 11))
                            .foregroundColor(.themeText3)
                    }

                    // 备份中心
                    section("备份与恢复") {
                        HStack(spacing: 10) {
                            Button("打开备份中心") { showBackupCenter = true }
                                .macPrimaryButton()
                            Button("立即快速备份") { quickBackup() }
                                .macSecondaryButton()
                            Button("立即全量备份") { fullBackup() }
                                .macSecondaryButton()
                            Spacer()
                        }
                        Text("快速备份含经营数据+房源字段；全量备份另含实拍媒体。可自动上传云端。")
                            .font(.system(size: 11))
                            .foregroundColor(.themeText3)
                    }

                    // 数据管理
                    section("数据管理") {
                        HStack(spacing: 10) {
                            Button("回收站") { showTrash = true }
                                .macSecondaryButton()
                            Button("工具（导入导出/日志）") { showUtility = true }
                                .macSecondaryButton()
                            Spacer()
                        }
                    }

                    // 其他
                    section("其他") {
                        HStack(spacing: 10) {
                            Button("使用说明") { showUserGuide = true }
                                .macSecondaryButton()
                            Button("查看完整功能报告") { openReport() }
                                .macSecondaryButton()
                            Spacer()
                        }
                    }

                    // 关于
                    section("关于") {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("公寓管家 Mac 版")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("版本 \(MacBridge.appVersion)（构建 \(MacBridge.appBuild)）")
                                    .font(.system(size: 12))
                                    .foregroundColor(.themeText2)
                                Text("数据存储：\(DataRoot.directory.path)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.themeText3)
                                    .lineLimit(1)
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
        .sheet(isPresented: $showShareSettings) {
            HouseSettingsView(manager: manager, houseContext: houseContext) { showShareSettings = false }
        }
        .sheet(isPresented: $showBackupCenter) {
            BackupCenterViews(manager: manager) { showBackupCenter = false }
        }
        .sheet(isPresented: $showTrash) {
            TrashView(manager: manager) { showTrash = false }
        }
        .sheet(isPresented: $showUtility) {
            UtilityView(manager: manager) { showUtility = false }
        }
        .sheet(isPresented: $showUserGuide) {
            UserGuideView(manager: manager) { showUserGuide = false }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
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
            case .success:
                MacToastCenter.show("快速备份完成")
            case .failure(let msg):
                MacToastCenter.show("备份失败：\(msg)")
            }
        }
    }

    private func fullBackup() {
        Task {
            let result = await BackupV5Manager.runFullBackup(mainContext: manager.mainContext,
                                                             houseContext: manager.houseContext,
                                                             uploadCloud: CosConfig.load() != nil)
            switch result {
            case .success:
                MacToastCenter.show("全量备份完成")
            case .failure(let msg):
                MacToastCenter.show("备份失败：\(msg)")
            }
        }
    }

    private func openReport() {
        MacBridge.openURL("https://aka.doubaocdn.com/s/BM7BmY6Tab")
    }
}
