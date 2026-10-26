import SwiftUI
import SwiftData
import AppKit
import UserNotifications

// MARK: - 数据根目录（macOS 标准：~/Library/Application Support/公寓管家Mac）

enum DataRoot {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("公寓管家Mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 经营数据库（主容器 default.store）
    static var defaultStoreURL: URL { DataRoot.directory.appendingPathComponent("default.store") }

    /// 房源数据库（housekeeper.store）
    static var houseStoreURL: URL { DataRoot.directory.appendingPathComponent("housekeeper.store") }

    /// 备份目录（用户可访问：快速/全量 zip）
    static var backupsDirectory: URL {
        let dir = DataRoot.directory.appendingPathComponent("备份", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 房源媒体目录
    static var mediaDirectory: URL {
        let dir = DataRoot.directory.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 分享缓存目录
    static var shareCacheDirectory: URL {
        let dir = DataRoot.directory.appendingPathComponent("ShareCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// COS 配置备份目录
    static var cosConfigDirectory: URL {
        let dir = DataRoot.directory.appendingPathComponent("CosConfig", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 日志目录
    static var logsDirectory: URL {
        let dir = DataRoot.directory.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 旧版 JSON 备份迁移目录
    static var legacyBackupDirectory: URL {
        let dir = DataRoot.directory.appendingPathComponent("旧版备份", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var qrcodeURL: URL { DataRoot.directory.appendingPathComponent("qrcode.png") }

    static func ensureAll() {
        _ = directory
        _ = backupsDirectory
        _ = mediaDirectory
        _ = shareCacheDirectory
        _ = cosConfigDirectory
        _ = logsDirectory
        _ = legacyBackupDirectory
    }
}

// MARK: - 双容器（主经营数据 + 房源数据）

/// 房源容器环境键
private struct HouseModelContextKey: EnvironmentKey {
    static let defaultValue: ModelContext? = nil
}

extension EnvironmentValues {
    var houseModelContext: ModelContext? {
        get { self[HouseModelContextKey.self] }
        set { self[HouseModelContextKey.self] = newValue }
    }
}

@main
struct GongyuGuanjiaMacApp: App {
    @State private var mainContainer: ModelContainer
    @State private var houseContainer: ModelContainer

    // 初始化：创建双容器（失败时进入内存临时模式并弹警告）
    init() {
        // 强制 App 内语言为中文
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")

        // 建立目录骨架
        DataRoot.ensureAll()

        // 双容器：容器级 schema 必须是所有配置模型的并集（13 经营 + 2 房源），否则 SwiftData 启动 fatalError
        let schema = Schema([
            DealRecord.self, Property.self, PayoutRecord.self,
            RentMonthRecord.self, UtilityQuarterRecord.self, UtilitySettlementRecord.self,
            UtilitySettlementHistory.self, TodoItem.self,
            MiscIncome.self, MiscExpense.self,
            PayoutMonthRecord.self, PayoutUtilityRecord.self, ProfitCalculation.self,
            House.self, MediaItem.self,
        ])
        // 主容器（经营数据）
        let mainConfig = ModelConfiguration("Main", schema: Schema([
            DealRecord.self, Property.self, PayoutRecord.self,
            RentMonthRecord.self, UtilityQuarterRecord.self, UtilitySettlementRecord.self,
            UtilitySettlementHistory.self, TodoItem.self,
            MiscIncome.self, MiscExpense.self,
            PayoutMonthRecord.self, PayoutUtilityRecord.self, ProfitCalculation.self
        ]), url: DataRoot.defaultStoreURL)
        // 房源容器
        let houseConfig = ModelConfiguration("House", schema: Schema([
            House.self, MediaItem.self
        ]), url: DataRoot.houseStoreURL)

        var main: ModelContainer?
        var house: ModelContainer?
        do {
            main = try ModelContainer(for: schema, configurations: [mainConfig, houseConfig])
            house = main
        } catch {
            // 降级：隔离损坏 store 后重试
            let fm = FileManager.default
            for url in [DataRoot.defaultStoreURL, DataRoot.houseStoreURL] {
                if fm.fileExists(atPath: url.path) {
                    let backup = url.deletingLastPathComponent()
                        .appendingPathComponent("backup_\(Int(Date().timeIntervalSince1970))_\(url.lastPathComponent)")
                    try? fm.moveItem(at: url, to: backup)
                }
            }
            do {
                main = try ModelContainer(for: schema, configurations: [mainConfig, houseConfig])
                house = main
            } catch {
                do {
                    main = try ModelContainer(for: schema, configurations: [mainConfig, houseConfig])
                    house = main
                } catch {
                    // 内存临时模式
                    let memMain = ModelConfiguration("Main", schema: Schema([DealRecord.self, Property.self, PayoutRecord.self,
                                                                             RentMonthRecord.self, UtilityQuarterRecord.self, UtilitySettlementRecord.self,
                                                                             UtilitySettlementHistory.self, TodoItem.self,
                                                                             MiscIncome.self, MiscExpense.self,
                                                                             PayoutMonthRecord.self, PayoutUtilityRecord.self, ProfitCalculation.self]), isStoredInMemoryOnly: true)
                    let memHouse = ModelConfiguration("House", schema: Schema([House.self, MediaItem.self]), isStoredInMemoryOnly: true)
                    main = try? ModelContainer(for: schema, configurations: [memMain, memHouse])
                    house = main
                    if main == nil {
                        fatalError("数据库无法创建")
                    }
                }
            }
        }
        _mainContainer = State(initialValue: main!)
        _houseContainer = State(initialValue: house!)
        GlobalContainers.main = mainContainer
        GlobalContainers.house = houseContainer

        // 通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UNUserNotificationCenter.current().delegate = NotificationClickHandler.shared
    }

    var body: some Scene {
        WindowGroup {
            MainSidebar()
                .environment(\.modelContext, mainContainer.mainContext)
                .environment(\.houseModelContext, houseContainer.mainContext)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

/// 通知点击处理器：点击通知切到对应板块
final class NotificationClickHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationClickHandler()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let tab = userInfo["tab"] as? Int {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .macSwitchTab, object: nil, userInfo: ["tab": tab])
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let macSwitchTab = Notification.Name("macSwitchTab")
    static let macHouseChanged = Notification.Name("macHouseChanged")
    static let macDataChanged = Notification.Name("macDataChanged")
    static let macBackupCenterMessage = Notification.Name("macBackupCenterMessage")
}
