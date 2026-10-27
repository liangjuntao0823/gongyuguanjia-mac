import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 房源分享设置（云配置 / 名片 / 二维码 / 水印 / 压缩开关 / 选房链接 / 刷新缓存）
// 与 iOS 版同入口逻辑：名片姓名电话、二维码、水印、压缩开关都集中在这里

struct HouseSettingsView: View {
    @ObservedObject var manager: DataManager
    @Environment(\.houseModelContext) private var houseContext
    let onClose: () -> Void

    // 云配置
    @State private var bucket = ""
    @State private var region = "ap-hongkong"
    @State private var secretId = ""
    @State private var secretKey = ""
    @State private var customDomain = ""
    @State private var functionURL = ""
    @State private var username = ""
    @State private var adminPassword = ""
    @State private var verifyMessage = ""
    @State private var verifying = false

    // 名片
    @State private var shareName = ""
    @State private var sharePhone = ""
    @State private var shareRecords: [ShareRecordItem] = []
    @State private var shareRecordsLoaded = false
    @State private var shareRecordsError: String?
    @State private var copiedShareURL: String?

    // 水印
    @State private var wmEnabled = true
    @State private var wmText = ""

    // 压缩
    @State private var compressUpload = true

    // 选房链接
    @State private var roomsLink = ""
    @State private var generatingRooms = false
    @State private var roomsMessage = ""
    @State private var roomsLinkExpiry = 2   // 选房链接有效期（天），默认 2，iOS 同 key

    @State private var qrPreview: NSImage?
    @State private var hasQR = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("房源分享设置")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }
                    .macSecondaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 云配置
                    sectionCard("云端配置（与 iOS 版共用）") {
                        Group {
                            TextField("用户名（数据隔离）", text: $username)
                            TextField("存储桶", text: $bucket)
                            TextField("地域", text: $region)
                            SecureField("SecretId", text: $secretId)
                            SecureField("SecretKey", text: $secretKey)
                            TextField("自定义域名（微信卡片必需）", text: $customDomain)
                            TextField("云函数地址（选房/统计用）", text: $functionURL)
                        }
                        .textFieldStyle(.roundedBorder)

                        if !verifyMessage.isEmpty {
                            Text(verifyMessage)
                                .font(.system(size: 14))
                                .foregroundColor(verifyMessage.contains("✓") ? .themeAccent : .themeDanger)
                        }
                        HStack {
                            Button(verifying ? "验证中…" : "保存并验证") { saveAndVerify() }
                                .macPrimaryButton()
                                .disabled(verifying)
                            Button("清空配置") {
                                CosConfig.clear()
                                verifyMessage = "配置已清空"
                            }
                            .macSecondaryButton()
                        }
                    }

                    // 名片信息
                    sectionCard("名片信息（分享 H5 / 选房链接）") {
                        TextField("姓名", text: $shareName)
                            .textFieldStyle(.roundedBorder)
                        TextField("电话", text: $sharePhone)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("保存名片") { saveCard() }
                                .macPrimaryButton()
                            Button("清除二维码") { clearQR() }
                                .macSecondaryButton()
                            Spacer()
                            if hasQR {
                                if let img = qrPreview {
                                    Image(nsImage: img)
                                        .resizable()
                                        .frame(width: 56, height: 56)
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }

                    // 水印
                    sectionCard("分享页水印") {
                        Toggle("分享页加水印", isOn: $wmEnabled)
                        TextField("水印文本", text: $wmText)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("保存水印") { saveWatermark() }
                                .macPrimaryButton()
                            Button("恢复默认") {
                                WatermarkSettingsStore.resetToDefault()
                                loadWatermark()
                                MacToastCenter.show("已恢复默认水印")
                            }
                            .macSecondaryButton()
                        }
                    }

                    // 压缩上传
                    sectionCard("上传设置") {
                        Toggle("新增媒体压缩后上传（省流量、上传更快）", isOn: $compressUpload)
                            .onChange(of: compressUpload) { _, newValue in
                                MediaSettingsStore.compressUpload = newValue
                            }
                        Text("关闭后视频/图片原样上传，画质无损但较慢。")
                            .font(.system(size: 13))
                            .foregroundColor(.themeText3)
                    }

                    // 选房链接
                    sectionCard("公开选房链接") {
                        Text("生成一个「米兰公馆 · 在租房源」H5，自动列出所有未出租房源，支持按户型筛选。")
                            .font(.system(size: 14))
                            .foregroundColor(.themeText2)
                        HStack(spacing: 10) {
                            Text("链接有效期").font(.system(size: 15)).foregroundColor(.themeText2)
                            Picker("", selection: $roomsLinkExpiry) {
                                Text("1 天").tag(1)
                                Text("2 天").tag(2)
                                Text("3 天").tag(3)
                                Text("7 天").tag(7)
                                Text("15 天").tag(15)
                                Text("30 天").tag(30)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 100)
                            .onChange(of: roomsLinkExpiry) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "roomsLinkExpiryDays")
                                roomsMessage = "已设为 \(newValue) 天：下次「生成/刷新」按新有效期生效"
                            }
                            Spacer()
                        }
                        HStack {
                            Button(generatingRooms ? "生成中…" : "生成 / 刷新选房链接") { generateRoomsLink() }
                                .macPrimaryButton()
                                .disabled(generatingRooms)
                            Button("复制链接") {
                                if !roomsLink.isEmpty {
                                    MacBridge.copy(roomsLink)
                                    MacToastCenter.show("链接已复制")
                                }
                            }
                            .macSecondaryButton()
                            .disabled(roomsLink.isEmpty)
                            Button("浏览器打开") {
                                if !roomsLink.isEmpty { MacBridge.openURL(roomsLink) }
                            }
                            .macSecondaryButton()
                            .disabled(roomsLink.isEmpty)
                        }
                        if !roomsMessage.isEmpty {
                            Text(roomsMessage)
                                .font(.system(size: 14))
                                .foregroundColor(roomsMessage.contains("失败") ? .themeDanger : .themeAccent)
                        }
                        if !roomsLink.isEmpty {
                            Text(roomsLink)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.themeText2)
                                .textSelection(.enabled)
                        }
                    }

                    // 后台口令
                    sectionCard("云端统计后台口令") {
                        SecureField("后台口令（与 iOS 版一致）", text: $adminPassword)
                            .textFieldStyle(.roundedBorder)
                        Button("保存口令") {
                            if !adminPassword.isEmpty {
                                CloudConfig.adminPassword = adminPassword
                                MacToastCenter.show("后台口令已保存")
                            }
                        }
                        .macPrimaryButton()
                    }

                    // 分享记录与访问统计（对齐 iOS v1.55：云端 do_shares 按用户名过滤）
                    sectionCard("分享记录（选房链接访问统计）") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("分享过的选房链接（云端按用户名隔离）")
                                    .font(.system(size: 12))
                                    .foregroundColor(.themeText3)
                                Spacer()
                                Button {
                                    loadShareRecords()
                                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                                .macSecondaryButton()
                            }
                            if let err = shareRecordsError {
                                Text(err).font(.system(size: 12)).foregroundColor(.themeDanger)
                            } else if shareRecords.isEmpty {
                                Text(shareRecordsLoaded ? "暂无分享记录，分享过房源后显示在这里。" : "加载分享记录…")
                                    .font(.system(size: 12))
                                    .foregroundColor(.themeText3)
                                    .padding(.vertical, 4)
                            } else {
                                ScrollView(.vertical, showsIndicators: true) {
                                    VStack(spacing: 6) {
                                        ForEach(shareRecords) { r in
                                            HStack(spacing: 8) {
                                                Text(r.room).font(.system(size: 13, weight: .bold))
                                                Text(r.mode).font(.system(size: 11))
                                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                                    .background(Color.accentColor.opacity(0.12))
                                                    .clipShape(Capsule())
                                                Spacer()
                                                Text(r.time).font(.system(size: 11)).foregroundColor(.themeText3)
                                                Button {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(r.url, forType: .string)
                                                    copiedShareURL = r.url
                                                    MacToastCenter.show("链接已复制")
                                                } label: {
                                                    Label(copiedShareURL == r.url ? "已复制" : "复制链接",
                                                          systemImage: copiedShareURL == r.url ? "checkmark" : "doc.on.doc")
                                                        .font(.system(size: 11))
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundColor(.accentColor)
                                            }
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                                .frame(maxHeight: 160)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .frame(width: 620, height: 700)
        .background(Color.themeBg)
        .onAppear {
            loadAll()
        }
    }

    // MARK: - 分享记录

    private func loadShareRecords() {
        shareRecordsError = nil
        shareRecordsLoaded = false
        let u = CloudUser.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        Task {
            do {
                let data = try await CosUploader.cloudCall(params: [
                    ("act", "shares"), ("k", CloudConfig.passwordHash), ("u", u)
                ])
                let obj = try JSONDecoder().decode(ShareRecordsResponse.self, from: data)
                guard obj.ok else {
                    await MainActor.run {
                        shareRecordsError = "云函数未返回分享记录（请确认函数已部署）"
                        shareRecordsLoaded = true
                    }
                    return
                }
                await MainActor.run {
                    shareRecords = obj.records
                    shareRecordsLoaded = true
                }
            } catch {
                await MainActor.run {
                    shareRecordsError = "加载失败：\(error.localizedDescription)"
                    shareRecordsLoaded = true
                }
            }
        }
    }

    // MARK: - 加载

    private func loadAll() {
        if let config = CosConfig.load() {
            bucket = config.bucket
            region = config.region
            secretId = config.secretId
            secretKey = config.secretKey
            customDomain = config.customDomain
        }
        functionURL = CloudConfig.functionURL
        username = CloudUser.username
        adminPassword = CloudConfig.adminPassword
        shareName = ShareNameStore.displayName
        sharePhone = ShareNameStore.displayPhone
        let wm = WatermarkSettingsStore.current
        wmEnabled = wm.enabled
        wmText = wm.text
        compressUpload = MediaSettingsStore.compressUpload
        let exp = UserDefaults.standard.integer(forKey: "roomsLinkExpiryDays")
        roomsLinkExpiry = (1...30).contains(exp) ? exp : 2
        hasQR = QrcodeStore.exists()
        if hasQR, let data = QrcodeStore.loadData() {
            qrPreview = NSImage(data: data)
        }
    }

    private func loadWatermark() {
        let wm = WatermarkSettingsStore.current
        wmEnabled = wm.enabled
        wmText = wm.text
    }

    // MARK: - 保存

    private func saveAndVerify() {
        let config = CosConfig(bucket: bucket.trimmingCharacters(in: .whitespaces),
                               region: region.trimmingCharacters(in: .whitespaces),
                               secretId: secretId.trimmingCharacters(in: .whitespaces),
                               secretKey: secretKey.trimmingCharacters(in: .whitespaces),
                               customDomain: customDomain.trimmingCharacters(in: .whitespaces))
        guard config.isValid else {
            verifyMessage = "请填写完整的存储桶/地域/密钥"
            return
        }
        CosConfig.save(config)
        if !username.isEmpty { CloudUser.username = username }
        if !functionURL.isEmpty { CloudConfig.functionURL = functionURL }
        if !adminPassword.isEmpty { CloudConfig.adminPassword = adminPassword }

        verifying = true
        verifyMessage = "正在验证…"
        Task {
            do {
                _ = try await CosUploader.verifyConnection(config: config)
                verifyMessage = "✓ 连接成功（自定义域名 \(config.customDomain.isEmpty ? "未填" : config.customDomain)）"
                // 验证通过后自动推送一次房源到云端账本，保证互通
                _ = await manager.pushToCloud()
            } catch {
                verifyMessage = "连接失败：\(error.localizedDescription)"
            }
            verifying = false
        }
    }

    private func saveCard() {
        ShareNameStore.save(name: shareName.trimmingCharacters(in: .whitespaces),
                            phone: sharePhone.trimmingCharacters(in: .whitespaces))
        MacToastCenter.show("名片已保存")
    }

    private func clearQR() {
        QrcodeStore.clear()
        hasQR = false
        qrPreview = nil
        MacToastCenter.show("二维码已清除")
    }

    private func saveWatermark() {
        var wm = WatermarkSettingsStore.current
        wm.enabled = wmEnabled
        wm.text = wmText
        WatermarkSettingsStore.current = wm
        MacToastCenter.show("水印设置已保存")
    }

    // MARK: - 选房链接

    private func generateRoomsLink() {
        guard let config = CosConfig.load() else {
            roomsMessage = "失败：请先配置云端"
            return
        }
        guard !CloudConfig.functionURL.isEmpty else {
            roomsMessage = "失败：未填写云函数地址（选房页需要）"
            return
        }
        generatingRooms = true
        roomsMessage = ""
        Task {
            do {
                // 先推送房源到账本（保证选房页有最新数据）
                _ = await manager.pushToCloud()
                // 上传名片二维码（若有）
                var qrUploaded = false
                if let qrJPEG = CosUploader.makeQRCodeJPEG() {
                    try? await CosUploader.upload(data: qrJPEG, to: CloudUser.qrPath, contentType: "image/jpeg", config: config)
                    qrUploaded = true
                }
                _ = qrUploaded
                // 生成壳页面并上传：先删除旧壳（旧链接立即失效，iOS v1.55 同逻辑），再按有效期生成新链接
                let shellPath = CloudUser.roomsIndexPath
                try? await CosUploader.deleteObject(path: shellPath, config: config)
                let expirySeconds = roomsLinkExpiry * 86400
                let shellURL = (try CosUploader.presignedGetURL(for: shellPath, expires: expirySeconds, config: config)).absoluteString
                let html = CosUploader.buildRoomsShellHTML(config: config, shellURL: shellURL)
                try await CosUploader.upload(data: Data(html.utf8), to: shellPath, contentType: "text/html", config: config)
                roomsLink = shellURL
                roomsMessage = "✓ 选房链接已生成（有效期 \(roomsLinkExpiry) 天），微信打开即网页（非下载文件），改完刷新即最新"
                BackupLogStore.log("生成选房链接", detail: "\(roomsLink)", kind: "local")
            } catch {
                roomsMessage = "失败：\(error.localizedDescription)"
            }
            generatingRooms = false
        }
    }

    // MARK: - 区块

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
    }
}


// MARK: - 分享记录（云函数 do_shares 返回）

struct ShareRecordItem: Codable, Identifiable {
    var id: String { url }
    let room: String
    let mode: String
    let time: String
    let url: String
}

struct ShareRecordsResponse: Codable {
    let ok: Bool
    let records: [ShareRecordItem]
}
