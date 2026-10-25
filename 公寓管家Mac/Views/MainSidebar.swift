import SwiftUI
import SwiftData

// MARK: - 主界面：macOS 标准侧边栏 + 主内容区
// 所有弹窗/详情页都带明确关闭按钮，不依赖滑屏手势

struct MainSidebar: View {
    @Environment(\.modelContext) private var mainContext
    @Environment(\.houseModelContext) private var houseContext
    @StateObject private var manager: DataManager
    @State private var showInitWizard = false
    @State private var toastMessage: String?

    init() {
        let mc = ModelContext(GlobalContainers.main)
        let hc = ModelContext(GlobalContainers.house)
        _manager = StateObject(wrappedValue: DataManager(mainContext: mc, houseContext: hc))
    }

    var body: some View {
        HStack(spacing: 0) {
            // 侧边栏
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("公寓管家")
                        .font(.system(size: 17, weight: .bold))
                        .padding(.leading, 14)
                        .padding(.top, 16)
                    Text("Mac 版 · v\(MacBridge.appVersion)")
                        .font(.system(size: 11))
                        .foregroundColor(.themeText3)
                        .padding(.leading, 14)
                        .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

                ForEach(MainTab.allCases) { tab in
                    Button {
                        manager.selectedTab = tab
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: manager.selectedTab == tab ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(manager.selectedTab == tab ? Color.white : Color.themeText)
                        .background(manager.selectedTab == tab ? Color.themeAccent : Color.clear)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
                Spacer()

                // 底部用户信息
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前用户：\(CloudUser.displayName)")
                        .font(.system(size: 12))
                    Text("云配置：\(CosConfig.load() != nil ? "已配置" : "未配置")")
                        .font(.system(size: 12))
                        .foregroundColor(CosConfig.load() != nil ? .themeAccent : .themeDanger)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.07))
            }
            .frame(width: 190)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))

            Divider()

            // 主内容区
            Group {
                switch manager.selectedTab {
                case .dashboard: DashboardView(manager: manager)
                case .houses: HouseListView(manager: manager)
                case .deals: DealsView(manager: manager)
                case .rents: RentCollectionView(manager: manager)
                case .payouts: PayoutView(manager: manager)
                case .profit: ProfitView(manager: manager)
                case .settings: SettingsView(manager: manager, houseContext: houseContext)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.themeBg)
        .macToast()
        .onReceive(NotificationCenter.default.publisher(for: .macSwitchTab)) { note in
            if let tab = note.userInfo?["tab"] as? Int, tab >= 0, tab < MainTab.allCases.count {
                manager.selectedTab = MainTab.allCases[tab]
            }
        }
        .onAppear {
            // 启动：自动备份检查
            CloudBackupService.runAutoBackupIfNeeded(mainContext: mainContext, houseContext: houseContext)
            // 未配置云端时提示初始化
            if CosConfig.load() == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showInitWizard = true
                }
            }
        }
        .sheet(isPresented: $showInitWizard) {
            InitWizardView(manager: manager) {
                showInitWizard = false
            }
        }
    }
}

// MARK: - 全局容器（App init 后填充，供 MainSidebar 创建独立 ModelContext）

enum GlobalContainers {
    static var main: ModelContainer!
    static var house: ModelContainer!
}

// MARK: - 首次使用向导（云配置 + 用户名）

struct InitWizardView: View {
    let manager: DataManager
    let onClose: () -> Void

    @State private var bucket = ""
    @State private var region = "ap-hongkong"
    @State private var secretId = ""
    @State private var secretKey = ""
    @State private var customDomain = "share.fangyuan88.site"
    @State private var functionURL = ""
    @State private var username = ""
    @State private var testing = false
    @State private var message = ""
    @State private var success = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("首次使用 · 云端配置")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Text("填写与 iOS 版相同的腾讯云 COS 配置和云函数地址，房源数据即可与 iOS 版互通。")
                .font(.system(size: 12))
                .foregroundColor(.themeText2)

            Group {
                TextField("用户名（数据隔离用，如 涛）", text: $username)
                TextField("存储桶", text: $bucket)
                TextField("地域（如 ap-hongkong）", text: $region)
                SecureField("SecretId", text: $secretId)
                SecureField("SecretKey", text: $secretKey)
                TextField("自定义域名（如 share.fangyuan88.site）", text: $customDomain)
                TextField("云函数地址", text: $functionURL)
            }
            .textFieldStyle(.roundedBorder)

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(success ? .themeAccent : .themeDanger)
            }

            HStack {
                Button("保存并验证") {
                    saveAndVerify()
                }
                .macPrimaryButton()
                Spacer()
                Button("跳过，稍后设置") {
                    onClose()
                }
                .macSecondaryButton()
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            // 预填已有配置
            if let config = CosConfig.load() {
                bucket = config.bucket
                region = config.region
                secretId = config.secretId
                secretKey = config.secretKey
                customDomain = config.customDomain
            }
            functionURL = CloudConfig.functionURL
            username = CloudUser.username
        }
    }

    private func saveAndVerify() {
        let config = CosConfig(bucket: bucket.trimmingCharacters(in: .whitespaces),
                               region: region.trimmingCharacters(in: .whitespaces),
                               secretId: secretId.trimmingCharacters(in: .whitespaces),
                               secretKey: secretKey.trimmingCharacters(in: .whitespaces),
                               customDomain: customDomain.trimmingCharacters(in: .whitespaces))
        guard config.isValid else {
            message = "请填写完整的存储桶/地域/密钥"
            success = false
            return
        }
        CosConfig.save(config)
        if !username.isEmpty { CloudUser.username = username }
        if !functionURL.isEmpty { CloudConfig.functionURL = functionURL }

        testing = true
        message = "正在验证云端连接…"
        Task {
            do {
                _ = try await CosUploader.verifyConnection(config: config)
                success = true
                message = "✓ 连接成功！可以开始使用（若云函数地址留空，选房链接功能不可用）"
            } catch {
                success = false
                message = "连接失败：\(error.localizedDescription)（已保存配置，可稍后在设置里重试）"
            }
            testing = false
        }
    }
}
