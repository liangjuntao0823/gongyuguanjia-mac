import SwiftUI
import AppKit

// MARK: - 主题（与 iOS 版视觉一致：深绿房源主题 + 浅色经营主题；v1.2.12 支持白天/黑夜/跟随系统）

// 外观模式（UserDefaults key: themeMode = day / night / system）
enum ThemeMode: String, CaseIterable {
    case day = "day"
    case night = "night"
    case system = "system"
    var label: String {
        switch self {
        case .day: return "白天"
        case .night: return "黑夜"
        case .system: return "跟随系统"
        }
    }
}

enum ThemeManager {
    static var mode: ThemeMode {
        get { ThemeMode(rawValue: UserDefaults.standard.string(forKey: "themeMode") ?? "system") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "themeMode") }
    }
    static var isDark: Bool {
        switch mode {
        case .day: return false
        case .night: return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
}

extension Color {
    static var themeBg: Color { ThemeManager.isDark ? Color(red: 0.09, green: 0.10, blue: 0.10) : Color(red: 0.96, green: 0.96, blue: 0.95) }
    static var themePanel: Color { ThemeManager.isDark ? Color(red: 0.13, green: 0.14, blue: 0.14) : Color.themePanel }
    static var themeCard: Color { ThemeManager.isDark ? Color(red: 0.16, green: 0.17, blue: 0.17) : Color.white }
    static var themeHeader: Color { ThemeManager.isDark ? Color(red: 0.11, green: 0.12, blue: 0.12) : Color.themeHeader }
    static var themeText: Color { ThemeManager.isDark ? Color(red: 0.92, green: 0.93, blue: 0.92) : Color(red: 0.16, green: 0.19, blue: 0.18) }
    static var themeText2: Color { ThemeManager.isDark ? Color(red: 0.72, green: 0.74, blue: 0.72) : Color(red: 0.36, green: 0.39, blue: 0.38) }
    static var themeText3: Color { ThemeManager.isDark ? Color(red: 0.52, green: 0.55, blue: 0.53) : Color(red: 0.55, green: 0.58, blue: 0.57) }
    static var themeBorder: Color { ThemeManager.isDark ? Color(red: 0.28, green: 0.30, blue: 0.29) : Color(red: 0.88, green: 0.89, blue: 0.88) }
    static var themeAccent: Color { ThemeManager.isDark ? Color(red: 0.30, green: 0.72, blue: 0.44) : Color(red: 0.10, green: 0.48, blue: 0.30) }   // 深绿主色
    static var themeAccentLight: Color { ThemeManager.isDark ? Color(red: 0.14, green: 0.26, blue: 0.20) : Color(red: 0.85, green: 0.93, blue: 0.89) }
    static var themeAccentDark: Color { ThemeManager.isDark ? Color(red: 0.42, green: 0.75, blue: 0.53) : Color(red: 0.06, green: 0.36, blue: 0.22) } // 深绿强调
    static var themeDanger: Color { ThemeManager.isDark ? Color(red: 0.95, green: 0.42, blue: 0.38) : Color(red: 0.82, green: 0.28, blue: 0.24) }
    static var themeRed: Color { ThemeManager.isDark ? Color(red: 0.98, green: 0.42, blue: 0.38) : Color(red: 0.85, green: 0.25, blue: 0.22) }        // 红（逾期/负值）
    static var themeOrange: Color { ThemeManager.isDark ? Color(red: 1.0, green: 0.68, blue: 0.24) : Color(red: 0.94, green: 0.55, blue: 0.10) }
    static var themeWarning: Color { ThemeManager.isDark ? Color(red: 0.98, green: 0.75, blue: 0.28) : Color(red: 0.85, green: 0.60, blue: 0.10) }
    static var themeBlue: Color { ThemeManager.isDark ? Color(red: 0.38, green: 0.64, blue: 0.96) : Color(red: 0.10, green: 0.42, blue: 0.80) }
    static var themeAmber: Color { ThemeManager.isDark ? Color(red: 0.98, green: 0.75, blue: 0.28) : Color(red: 0.85, green: 0.60, blue: 0.10) }   // 琥珀（需结算水电）
    static var themeAccentWeak: Color { ThemeManager.isDark ? Color(red: 0.14, green: 0.26, blue: 0.20) : Color(red: 0.85, green: 0.93, blue: 0.89) } // 浅绿底（已刷新提示）

    /// 从十六进制字符串创建颜色（如 "7B61FF"）
    init(hex: String) {
        var value: UInt64 = 0
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        Scanner(string: hexStr).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - 通用格式工具

enum FormatKit {
    static let money: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func money(_ v: Double) -> String {
        money.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }

    static func money(_ v: Int) -> String {
        money.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static let month: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static func dateStr(_ d: Date) -> String { date.string(from: d) }
    static func dateTimeStr(_ d: Date) -> String { dateTime.string(from: d) }
    static func monthStr(_ d: Date) -> String { month.string(from: d) }
}
