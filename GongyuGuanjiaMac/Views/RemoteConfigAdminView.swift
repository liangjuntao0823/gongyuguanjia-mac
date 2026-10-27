import SwiftUI

// MARK: - 远程配置管理后台（对齐 iOS v1.80-1.82 RemoteConfigAdminView）
/// 读取：云函数 act=configGet（带口令）→ 未配置/为空时用默认模板填充
/// 保存：POST act=configSave（自动 version+1）→ 云端生效 + 写本地缓存（断网兜底）
/// 管理后台第 4 tab 入口：工作台 → 管理后台 → 远程配置

struct ConfigGetResponse: Decodable {
    var ok: Bool
    var config: RemoteConfig.Payload?
}

struct ConfigSaveResponse: Decodable {
    var ok: Bool
    var version: Int?
}

struct RemoteConfigAdminView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = RemoteConfig.Payload()
    @State private var loaded = false
    @State private var loading = false
    @State private var saving = false
    @State private var statusText = ""
    // 更新日志输入
    @State private var newCLVersion = ""
    @State private var newCLDate = ""
    @State private var newCLChanges = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("远程配置").font(.system(size: 18, weight: .bold))
                Spacer()
                Button(loaded ? "重新加载" : "加载云端配置") { loadConfig() }
                    .macSecondaryButton()
                    .disabled(loading)
                Button("保存并发布") { saveConfig() }
                    .macPrimaryButton()
                    .disabled(saving || !loaded)
            }
            if loading { ProgressView("加载中…").controlSize(.small) }
            if saving { ProgressView("保存中…").controlSize(.small) }

            if !statusText.isEmpty {
                Text(statusText).font(.system(size: 13)).foregroundColor(.themeText2)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 公告
                    configSection("公告") {
                        Toggle("启用公告", isOn: Binding(get: { config.announcement?.enabled ?? false },
                                                          set: { v in if config.announcement == nil { config.announcement = RemoteConfig.Announcement(enabled: v, text: "", link: nil) } else { config.announcement?.enabled = v } }))
                        TextField("公告内容", text: Binding(get: { config.announcement?.text ?? "" },
                                                           set: { v in if config.announcement == nil { config.announcement = RemoteConfig.Announcement(enabled: false, text: v, link: nil) } else { config.announcement?.text = v } }))
                        TextField("链接（可选）", text: Binding(get: { config.announcement?.link ?? "" },
                                                               set: { v in config.announcement?.link = v.isEmpty ? nil : v }))
                    }

                    // 最低版本
                    configSection("最低版本") {
                        TextField("最低版本号（如 1.2.6，留空不限制）", text: Binding(get: { config.minimumVersion ?? "" },
                                                                                  set: { v in config.minimumVersion = v.isEmpty ? nil : v }))
                    }

                    // 功能开关
                    configSection("功能开关") {
                        ForEach(Self.featureKeys, id: \.self) { key in
                            Toggle(Self.label(key), isOn: Binding(get: { config.features[key] ?? Self.featureDefaults[key] ?? false },
                                                                   set: { config.features[key] = $0 }))
                        }
                    }

                    // 数值参数
                    configSection("数值参数") {
                        ForEach(Self.paramKeys, id: \.self) { key in
                            HStack {
                                Text(Self.label(key)).frame(width: 180, alignment: .leading)
                                TextField("", value: Binding(get: { config.params[key] ?? Self.paramDefaults[key] ?? 0 },
                                                              set: { config.params[key] = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    // 提示文案
                    configSection("提示文案（tips）") {
                        ForEach(Self.tipKeys, id: \.self) { key in
                            TextField(Self.label(key), text: Binding(get: { config.tips[key] ?? "" },
                                                                      set: { config.tips[key] = $0 }))
                        }
                    }

                    // 帮助文案
                    configSection("帮助文案（helpTexts）") {
                        ForEach(Self.helpKeys, id: \.self) { key in
                            TextField(Self.label(key), text: Binding(get: { config.helpTexts[key] ?? "" },
                                                                      set: { config.helpTexts[key] = $0 }))
                        }
                    }

                    // 更新日志管理
                    configSection("更新日志（云端发布，App 端同步展示）") {
                        if let list = config.changelog, !list.isEmpty {
                            ForEach(list) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(entry.version)\(entry.date.map { " · \($0)" } ?? "")")
                                            .font(.system(size: 13, weight: .semibold))
                                        ForEach(entry.changes, id: \.self) { c in
                                            Text("· \(c)").font(.system(size: 12)).foregroundColor(.themeText2)
                                        }
                                    }
                                    Spacer()
                                    Button("删除") {
                                        config.changelog?.removeAll { $0.version == entry.version && $0.date == entry.date }
                                    }.macSecondaryButton()
                                }
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.themeBg.opacity(0.5)))
                            }
                        } else {
                            Text("暂无云端更新日志，可在下方添加").font(.system(size: 12)).foregroundColor(.themeText3)
                        }
                        Divider()
                        HStack {
                            TextField("版本号", text: $newCLVersion).textFieldStyle(.roundedBorder)
                            TextField("日期（可选）", text: $newCLDate).textFieldStyle(.roundedBorder)
                        }
                        TextField("改动内容（每行一条）", text: $newCLChanges)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("添加日志") { addChangelog() }.macSecondaryButton()
                            Spacer()
                        }
                    }

                    // 当前缓存
                    configSection("本地缓存") {
                        Text("\(RemoteConfig.summary)")
                            .font(.system(size: 13))
                            .foregroundColor(.themeText2)
                        Text("云端 config.json 优先；断网读本地缓存；均无则用内置默认值。")
                            .font(.system(size: 12)).foregroundColor(.themeText3)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 620)
        .onAppear {
            RemoteConfig.loadCache()
            config = RemoteConfig.current
            loaded = true
            statusText = "已加载本地缓存：\(RemoteConfig.summary)"
        }
    }

    private func configSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.themeText2)
            content()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.themeBg.opacity(0.4)))
    }

    // MARK: 读取

    private func loadConfig() {
        loading = true
        statusText = ""
        let u = CloudUser.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        Task {
            do {
                let data = try await CosUploader.cloudCall(params: [
                    ("act", "configGet"), ("k", CloudConfig.passwordHash), ("u", u)
                ])
                let obj = try JSONDecoder().decode(ConfigGetResponse.self, from: data)
                await MainActor.run {
                    loading = false
                    guard obj.ok else {
                        statusText = "加载失败：云函数未确认（请检查网络与口令）"
                        return
                    }
                    config = obj.config ?? Self.defaultTemplate()
                    loaded = true
                    statusText = "已加载云端配置 v\(config.version)"
                }
            } catch {
                await MainActor.run {
                    loading = false
                    statusText = "加载失败：无法连接云函数，请检查网络与地址"
                }
            }
        }
    }

    // MARK: 保存

    private func saveConfig() {
        saving = true
        statusText = ""
        config.version = (config.version > 0 ? config.version : 0) + 1
        var body = config
        body.updatedBy = CloudUser.username
        let u = CloudUser.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let base = URL(string: CloudConfig.functionURL),
              let comps = URLComponents(url: base.appending(queryItems: [
                URLQueryItem(name: "act", value: "configSave"),
                URLQueryItem(name: "k", value: CloudConfig.passwordHash),
                URLQueryItem(name: "u", value: u)
              ]), resolvingAgainstBaseURL: false),
              let url = comps.url,
              let payload = try? JSONEncoder().encode(body) else {
            saving = false
            statusText = "保存失败：参数无效"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let obj = try JSONDecoder().decode(ConfigSaveResponse.self, from: data)
                await MainActor.run {
                    saving = false
                    guard obj.ok else {
                        statusText = "保存失败：云函数未确认（请检查网络与口令）"
                        return
                    }
                    RemoteConfig.apply(body)
                    statusText = "已保存 ✓ 配置版本 v\(obj.version ?? body.version)，App 下次启动/同步即生效"
                }
            } catch {
                await MainActor.run {
                    saving = false
                    statusText = "保存失败：网络错误（\(error.localizedDescription)）"
                }
            }
        }
    }

    private func addChangelog() {
        let version = newCLVersion.trimmingCharacters(in: .whitespaces)
        guard !version.isEmpty else { return }
        let date = newCLDate.trimmingCharacters(in: .whitespaces)
        let changes = newCLChanges.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var list = config.changelog ?? []
        list.insert(RemoteConfig.ChangelogEntry(version: version, date: date.isEmpty ? nil : date, changes: changes), at: 0)
        config.changelog = list
        newCLVersion = ""
        newCLDate = ""
        newCLChanges = ""
    }

    // MARK: 配置项中文名（英文 key → 中文显示）

    private static func label(_ key: String) -> String {
        LABELS[key] ?? key
    }

    private static let LABELS: [String: String] = [
        // 功能开关
        "compressUpload": "上传压缩",
        "watermark": "分享水印",
        "autoBackup": "自动备份",
        "showOfflineRestore": "离线重建入口",
        "showRoomsShare": "选房分享入口",
        // 数值参数
        "autoBackupKeepDays": "自动备份保留天数（天）",
        // 提示文案
        "refreshDone": "刷新完成提示",
        "refreshNoChange": "刷新无变化提示",
        "refreshFail": "刷新失败提示",
        // 帮助文案
        "helpTexts": "帮助文案说明",
    ]

    private static let featureKeys = ["compressUpload", "watermark", "autoBackup", "showOfflineRestore", "showRoomsShare"]
    private static let featureDefaults: [String: Bool] = [
        "compressUpload": true, "watermark": true, "autoBackup": true,
        "showOfflineRestore": true, "showRoomsShare": true,
    ]
    private static let paramKeys = ["autoBackupKeepDays"]
    private static let paramDefaults: [String: Double] = ["autoBackupKeepDays": 30]
    private static let tipKeys = ["refreshDone", "refreshNoChange", "refreshFail"]
    private static let helpKeys: [String] = []

    /// 未配置/为空时的默认模板（与内置默认行为一致）
    static func defaultTemplate() -> RemoteConfig.Payload {
        var p = RemoteConfig.Payload()
        p.version = 0
        p.tips = ["refreshDone": "已刷新", "refreshNoChange": "已刷新，无变化", "refreshFail": "刷新失败，请检查网络"]
        p.features = featureDefaults
        p.params = paramDefaults
        p.helpTexts = [:]
        p.changelog = []
        return p
    }
}
