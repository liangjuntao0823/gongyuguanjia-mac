import SwiftUI
import AppKit

// MARK: - 账单模板设置（对齐 iOS BillTemplateSettingsView：固定文本 + 收款码 + 预览）
// Mac 标准：收款码用文件选择器，所有弹窗带明确关闭按钮

struct BillTemplateSettingsView: View {
    let onClose: () -> Void

    @AppStorage("billFixedTip") private var billFixedTip = "账单由人工录入，系统生成，如金额有误请与我联系！"
    @AppStorage("billGreeting") private var billGreeting = "尊敬的租客，感谢您选择我司提供的租赁服务！"
    @AppStorage("billDuePrefix") private var billDuePrefix = "您"
    @AppStorage("billDueSuffix") private var billDueSuffix = "前需支付房租账单明细如下："
    @AppStorage("billLateFeeTip") private var billLateFeeTip = "（请务必按时交租，逾期交租将按照租房合同约定计算滞纳金：月租金5%/天×天数）"
    @AppStorage("billSign") private var billSign = "谢谢  祝 商祺"
    @AppStorage("billQRAlipayFile") private var billQRAlipayFile = ""
    @AppStorage("billQRWechatFile") private var billQRWechatFile = ""

    @State private var alipayPreview: NSImage?
    @State private var wechatPreview: NSImage?
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("账单模板设置").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("完成") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionCard("固定文本（生成账单时实时生效）") {
                        Group {
                            TextField("顶部固定提示", text: $billFixedTip, axis: .vertical).lineLimit(1...3)
                            TextField("问候语", text: $billGreeting, axis: .vertical).lineLimit(1...3)
                            HStack(spacing: 6) {
                                TextField("引导语前段", text: $billDuePrefix)
                                Text("交租日期").font(.system(size: 14)).foregroundColor(.gray)
                                TextField("引导语后段", text: $billDueSuffix)
                            }
                            TextField("滞纳金提示", text: $billLateFeeTip, axis: .vertical).lineLimit(1...3)
                            TextField("落款", text: $billSign)
                        }
                        .textFieldStyle(.roundedBorder)
                    }

                    sectionCard("收款码") {
                        qrRow("支付宝收款码", file: $billQRAlipayFile, preview: $alipayPreview)
                        qrRow("微信收款码", file: $billQRWechatFile, preview: $wechatPreview)
                        Text("点击「更换」从文件中选择新收款码图片，立即生效；点击「清除」恢复内置默认收款码。")
                            .font(.system(size: 13)).foregroundColor(.themeText3)
                    }

                    sectionCard("预览") {
                        HStack(spacing: 10) {
                            Button("预览账单效果") { showPreview = true }.macPrimaryButton()
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(billFixedTip).font(.system(size: 15)).foregroundColor(.themeText3)
                            Text(billGreeting).font(.system(size: 15)).foregroundColor(.themeText3)
                            Text("\(billDuePrefix)2026年10月15日\(billDueSuffix)").font(.system(size: 15)).foregroundColor(.themeText3)
                            Text("电费：¥50.00 · 水费：¥20.00").font(.system(size: 15)).foregroundColor(.themeText3)
                            Text(billLateFeeTip).font(.system(size: 13)).foregroundColor(.themeText3)
                            Text(billSign).font(.system(size: 15)).foregroundColor(.themeText3)
                            // 收款码预览：与账单生成时一致并排展示
                            if alipayPreview != nil || wechatPreview != nil {
                                Divider().padding(.vertical, 4)
                                HStack(spacing: 16) {
                                    if let img = alipayPreview {
                                        VStack(spacing: 4) {
                                            Image(nsImage: img).resizable().frame(width: 72, height: 72).cornerRadius(8)
                                            Text("支付宝收款码").font(.system(size: 12)).foregroundColor(.themeText3)
                                        }
                                    }
                                    if let img = wechatPreview {
                                        VStack(spacing: 4) {
                                            Image(nsImage: img).resizable().frame(width: 72, height: 72).cornerRadius(8)
                                            Text("微信收款码").font(.system(size: 12)).foregroundColor(.themeText3)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.themeCard)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder))
                    }

                    Spacer(minLength: 16)
                }
                .padding(16)
            }
            .background(Color.themeBg)
        }
        .frame(width: 560, height: 620)
        .background(Color.themeBg)
        .onAppear { loadPreviews() }
        .alert("账单预览", isPresented: $showPreview) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("预览已在上方「预览」区实时展示：固定文本与收款码均按当前设置生成账单时的排版效果。")
        }
    }

    // MARK: 收款码行

    private func qrRow(_ title: String, file: Binding<String>, preview: Binding<NSImage?>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
            if let img = preview.wrappedValue {
                Image(nsImage: img).resizable().frame(width: 42, height: 42).cornerRadius(6)
            }
            Button("更换") { pickQR(file: file, preview: preview) }.macSecondaryButton()
            if !file.wrappedValue.isEmpty {
                Button("清除") {
                    if let url = qrURL(file.wrappedValue) { try? FileManager.default.removeItem(at: url) }
                    file.wrappedValue = ""
                    preview.wrappedValue = nil
                    MacToastCenter.show("已清除\(title)")
                }.macSecondaryButton()
            }
        }
    }

    // MARK: 动作

    private func pickQR(file: Binding<String>, preview: Binding<NSImage?>) {
        MacBridge.openFile(allowedTypes: [.image]) { url in
            guard let url, let img = NSImage(contentsOf: url) else {
                MacToastCenter.show("未选择有效图片")
                return
            }
            let name = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
            let dest = DataRoot.billDirectory.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: DataRoot.billDirectory, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: url, to: dest)
            file.wrappedValue = name
            preview.wrappedValue = img
            MacToastCenter.show("收款码已更新")
        }
    }

    private func qrURL(_ name: String) -> URL? {
        guard !name.isEmpty else { return nil }
        return DataRoot.billDirectory.appendingPathComponent(name)
    }

    private func loadPreviews() {
        if let img = loadQR(billQRAlipayFile) { alipayPreview = img }
        if let img = loadQR(billQRWechatFile) { wechatPreview = img }
    }

    private func loadQR(_ name: String) -> NSImage? {
        guard let url = qrURL(name) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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
}

// MARK: - 待补传媒体（对齐 iOS MediaPendingView：上传失败/待补传媒体集中查看与重试）

struct MediaPendingView: View {
    let onClose: () -> Void
    @State private var items: [HouseMediaUploadQueue.QueueItem] = []
    @State private var retrying = false
    @State private var isUploading = false
    @ObservedObject private var syncCenter = SyncTaskCenter.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("待补传媒体").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            Divider()

            // 进行中的同步任务卡片（对齐 iOS：设置-待补传媒体页顶部显示）
            if let t = syncCenter.task, t.isRunning {
                HStack(spacing: 10) {
                    ProgressView(value: t.fraction).progressViewStyle(.linear).frame(maxWidth: 160)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 13, weight: .semibold))
                        Text(t.current.isEmpty ? "\(t.done)/\(t.total)" : "\(t.done)/\(t.total) · \(t.current)")
                            .font(.system(size: 12)).foregroundColor(.themeText2)
                    }
                    Spacer()
                    Button("收起") { syncCenter.dismiss() }.macSecondaryButton()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("没有待补传任务").font(.system(size: 16, weight: .semibold))
                        Text("上传失败的媒体会自动保留在这里，可集中查看和重试")
                            .font(.system(size: 14)).foregroundColor(.themeText3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 10) {
                        Text("共 \(items.count) 个媒体待补传").font(.system(size: 15)).foregroundColor(.themeText2)
                        Spacer()
                        Button(retrying ? "重试中…" : "全部重试") {
                            retrying = true
                            Task {
                                await HouseMediaUploadQueue.shared.retryAllFailed()
                                await load()
                                retrying = false
                            }
                        }
                        .macPrimaryButton()
                        .disabled(retrying)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    List(items, id: \.fileName) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.kind == "video" ? "film" : "photo")
                                .foregroundColor(.themeText3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.fileName).font(.system(size: 15))
                                Text("房源：\(item.roomKey) · \(item.kind == "video" ? "视频" : "图片")")
                                    .font(.system(size: 13)).foregroundColor(.themeText3)
                            }
                            Spacer()
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(.themeAccent)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.themeBg)
        }
        .frame(width: 520, height: 420)
        .background(Color.themeBg)
        .onAppear {
            Task { await load() }
        }
    }

    private func load() async {
        items = await HouseMediaUploadQueue.shared.failedItems()
    }
}
