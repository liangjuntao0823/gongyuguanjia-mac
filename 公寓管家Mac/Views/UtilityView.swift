import SwiftUI
import SwiftData

// MARK: - 工具（Excel 导入导出 / 日志 / 缓存清理）

struct UtilityView: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var showLogs = false
    @State private var logsText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("工具")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }
                    .macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("数据导入导出") {
                        Text("Excel 导入导出为兼容格式（可用 Excel / WPS 打开），与 iOS 版一致。")
                            .font(.system(size: 11))
                            .foregroundColor(.themeText3)
                        Text("成交/收租记录在「成交」板块内导入导出。")
                            .font(.system(size: 11))
                            .foregroundColor(.themeText3)
                    }

                    section("日志") {
                        HStack(spacing: 10) {
                            Button("查看崩溃/操作日志") {
                                logsText = CrashLogCollector.logsText()
                                showLogs = true
                            }
                            .macSecondaryButton()
                            Button("清空日志") {
                                CrashLogCollector.clear()
                                MacToastCenter.show("日志已清空")
                            }
                            .macSecondaryButton()
                        }
                    }

                    section("缓存清理") {
                        HStack(spacing: 10) {
                            Button("清理分享缓存（旧 H5 页会失效，新页不受影响）") {
                                CosUploader.clearShareCache()
                                MacToastCenter.show("分享缓存已清理")
                            }
                            .macSecondaryButton()
                            Button("显示缓存目录") {
                                MacBridge.revealInFinder(DataRoot.directory)
                            }
                            .macSecondaryButton()
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 520)
        .background(Color.themeBg)
        .sheet(isPresented: $showLogs) {
            LogsSheet(text: logsText) { showLogs = false }
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
}

struct LogsSheet: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("日志")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }
                    .macPrimaryButton()
            }
            .padding(14)
            Divider()
            ScrollView {
                Text(text.isEmpty ? "暂无日志" : text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .frame(width: 560, height: 460)
    }
}
