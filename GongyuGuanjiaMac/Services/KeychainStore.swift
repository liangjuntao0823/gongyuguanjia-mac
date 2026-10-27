import Foundation

// MARK: - 本地配置存取
// v1.2.2 起改为 UserDefaults 存储（不再使用系统钥匙串）：
// 未签名/本地构建访问钥匙串会触发 macOS 授权弹窗并要求登录钥匙串密码，
// 导致 App 在无密码环境下无法读取云端配置。改为本地存储后不再弹窗，
// 云端配置需在设置中重新填写一次（可在 iOS 端设置里照抄同一份 COS 配置）。

enum KeychainStore {

    /// 键名前缀，避免与其他设置冲突
    private static func k(_ key: String) -> String { "kc." + key }

    static func save(_ value: String, for key: String) -> Bool {
        UserDefaults.standard.set(value, forKey: k(key))
        return true
    }

    static func load(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: k(key))
    }

    static func delete(_ key: String) {
        UserDefaults.standard.removeObject(forKey: k(key))
    }

    static func exists(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: k(key)) != nil
    }
}
