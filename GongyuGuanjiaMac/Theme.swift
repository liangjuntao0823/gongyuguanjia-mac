import SwiftUI
import AppKit

// MARK: - 主题（与 iOS 版视觉一致：深绿房源主题 + 浅色经营主题）

extension Color {
    static let themeBg = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let themePanel = Color(red: 0.99, green: 0.99, blue: 0.98)
    static let themeText = Color(red: 0.16, green: 0.19, blue: 0.18)
    static let themeText2 = Color(red: 0.36, green: 0.39, blue: 0.38)
    static let themeText3 = Color(red: 0.55, green: 0.58, blue: 0.57)
    static let themeBorder = Color(red: 0.88, green: 0.89, blue: 0.88)
    static let themeAccent = Color(red: 0.10, green: 0.48, blue: 0.30)   // 深绿主色
    static let themeAccentLight = Color(red: 0.85, green: 0.93, blue: 0.89)
    static let themeAccentDark = Color(red: 0.06, green: 0.36, blue: 0.22) // 深绿强调
    static let themeDanger = Color(red: 0.82, green: 0.28, blue: 0.24)
    static let themeRed = Color(red: 0.85, green: 0.25, blue: 0.22)        // 红（逾期/负值）
    static let themeOrange = Color(red: 0.94, green: 0.55, blue: 0.10)
    static let themeWarning = Color(red: 0.85, green: 0.60, blue: 0.10)
    static let themeBlue = Color(red: 0.10, green: 0.42, blue: 0.80)

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
