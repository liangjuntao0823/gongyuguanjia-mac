import SwiftUI
import SwiftData

// MARK: - 手动同步（Mac 形态：状态展示 + 云端同步引导，局域网扫码由云端同步替代）
// 对应 iOS ManualSyncView / MigrationView，Mac 端保留协议层（SyncCore/SyncDTO/Snapshot），
// 交互入口改为云端同步与备份迁移。

struct ManualSyncView: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var pendingCount = 0
    @State private var conflictCount = 0
    @State private var hasSynced = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("手动同步").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    infoCard("本机同步状态") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("待上传变更：\(pendingCount) 条")
                            Text("未解决冲突：\(conflictCount) 条")
                            Text(hasSynced ? "已建立同步基线（后续可继续增量同步）" : "尚未进行过手动同步（或基线已清空）")
                                .foregroundColor(.themeText3)
                        }
                        .font(.system(size: 13))
                    }
                    infoCard("说明") {
                        Text("Mac 版已内置同步协议层（SyncCore / SyncDTO / SwiftDataSyncSnapshot），与 iOS 版同一套数据结构。由于 Mac 无摄像头扫码，局域网扫码同步改为云端同步通道：在「设置 → 云端同步」中配置同一用户名，即可与 iOS 双向同步房源与经营数据。")
                            .font(.system(size: 12))
                            .foregroundColor(.themeText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    infoCard("数据迁移（对应 iOS MigrationView）") {
                        Text("iOS 版的 zfgj 迁移文件在 Mac 端以备份文件形态实现：在「设置 → 备份与恢复 → 打开备份中心」中，用「恢复」选择备份文件即可完整迁移经营数据+房源字段；全量备份还含实拍照片/视频。")
                            .font(.system(size: 12))
                            .foregroundColor(.themeText3)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("打开备份中心") { onClose() }
                                .macSecondaryButton()
                            Button("去云端同步") { onClose() }
                                .macPrimaryButton()
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 480)
        .onAppear {
            Task {
                let snap = await SyncStore.shared.snapshot()
                pendingCount = snap.pending.count
                conflictCount = snap.conflicts.count
                hasSynced = snap.cursor != nil
            }
        }
    }

    private func infoCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .bold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
    }
}
