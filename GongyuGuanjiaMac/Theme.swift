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
    // v1.2.14 对比度重设计：浅色更白（参考 iOS 白底深字）、暗色更亮文字更深背景，杜绝“灰底黑字看不清 / 反色后内容不可见”
    static var themeBg: Color { ThemeManager.isDark ? Color(red: 0.08, green: 0.09, blue: 0.09) : Color(red: 0.985, green: 0.985, blue: 0.98) }
    static var themePanel: Color { ThemeManager.isDark ? Color(red: 0.13, green: 0.14, blue: 0.14) : Color.white }
    static var themeCard: Color { ThemeManager.isDark ? Color(red: 0.17, green: 0.18, blue: 0.18) : Color.white }
    static var themeHeader: Color { ThemeManager.isDark ? Color(red: 0.10, green: 0.11, blue: 0.11) : Color(red: 0.965, green: 0.965, blue: 0.955) }
    static var themeText: Color { ThemeManager.isDark ? Color(red: 0.97, green: 0.975, blue: 0.97) : Color(red: 0.14, green: 0.17, blue: 0.16) }
    static var themeText2: Color { ThemeManager.isDark ? Color(red: 0.80, green: 0.82, blue: 0.80) : Color(red: 0.34, green: 0.37, blue: 0.36) }
    static var themeText3: Color { ThemeManager.isDark ? Color(red: 0.62, green: 0.65, blue: 0.63) : Color(red: 0.50, green: 0.53, blue: 0.52) }
    static var themeBorder: Color { ThemeManager.isDark ? Color(red: 0.38, green: 0.40, blue: 0.39) : Color(red: 0.87, green: 0.88, blue: 0.87) }
    static var themeAccent: Color { ThemeManager.isDark ? Color(red: 0.36, green: 0.80, blue: 0.52) : Color(red: 0.10, green: 0.48, blue: 0.30) }   // 深绿主色
    static var themeAccentLight: Color { ThemeManager.isDark ? Color(red: 0.14, green: 0.28, blue: 0.21) : Color(red: 0.85, green: 0.93, blue: 0.89) }
    static var themeAccentDark: Color { ThemeManager.isDark ? Color(red: 0.46, green: 0.80, blue: 0.58) : Color(red: 0.06, green: 0.36, blue: 0.22) } // 深绿强调
    static var themeDanger: Color { ThemeManager.isDark ? Color(red: 0.96, green: 0.46, blue: 0.42) : Color(red: 0.82, green: 0.28, blue: 0.24) }
    static var themeRed: Color { ThemeManager.isDark ? Color(red: 1.0, green: 0.48, blue: 0.44) : Color(red: 0.85, green: 0.25, blue: 0.22) }        // 红（逾期/负值）
    static var themeOrange: Color { ThemeManager.isDark ? Color(red: 1.0, green: 0.70, blue: 0.28) : Color(red: 0.94, green: 0.55, blue: 0.10) }
    static var themeWarning: Color { ThemeManager.isDark ? Color(red: 1.0, green: 0.78, blue: 0.32) : Color(red: 0.85, green: 0.60, blue: 0.10) }
    static var themeBlue: Color { ThemeManager.isDark ? Color(red: 0.45, green: 0.70, blue: 1.0) : Color(red: 0.10, green: 0.42, blue: 0.80) }
    static var themeAmber: Color { ThemeManager.isDark ? Color(red: 1.0, green: 0.78, blue: 0.32) : Color(red: 0.85, green: 0.60, blue: 0.10) }   // 琥珀（需结算水电）
    static var themeAccentWeak: Color { ThemeManager.isDark ? Color(red: 0.14, green: 0.28, blue: 0.21) : Color(red: 0.85, green: 0.93, blue: 0.89) } // 浅绿底（已刷新提示）

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
