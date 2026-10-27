import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 导出图片服务（Mac 桌面版：表格渲染成 PNG，对齐 iOS 导出图片功能）

/// 导出用表格视图（标题 + 导出时间 + 表头 + 数据行，纯 VStack 便于 ImageRenderer 完整渲染）
struct ExportTableView: View {
    let title: String
    let dateStr: String
    let headers: [String]
    let rows: [[String]]
    var highlightRow: Int? = nil   // 定位高亮（-1 = 无）

    private let headerBg = Color(red: 0.93, green: 0.94, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text("导出时间：\(dateStr)")
                .font(.system(size: 13))
                .foregroundColor(.gray)
            Divider()
            // 表头
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    Text(h)
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6).padding(.vertical, 5)
                }
            }
            .background(headerBg)
            // 数据行
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .lineLimit(1)
                    }
                }
                .background(idx == highlightRow ? Color.yellow.opacity(0.35) : (idx % 2 == 1 ? Color(red: 0.97, green: 0.97, blue: 0.98) : Color.white))
            }
        }
        .padding(14)
        .frame(width: 900)
        .background(Color.white)
    }
}

enum ExportImageService {

    /// 渲染表格为 PNG 并弹出保存面板（Mac 对齐 iOS「导出图片」）
    @MainActor
    static func exportTable(title: String, headers: [String], rows: [[String]],
                            filename: String, highlightRow: Int? = nil) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年M月d日 HH:mm"
        let view = ExportTableView(title: title, dateStr: df.string(from: Date()),
                                   headers: headers, rows: rows, highlightRow: highlightRow)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage else {
            MacToastCenter.show("导出图片失败：无法渲染")
            return
        }
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            MacToastCenter.show("导出图片失败：编码失败")
            return
        }
        let safeName = filename.replacingOccurrences(of: "/", with: "-")
        MacBridge.saveFile(defaultName: "\(safeName)_\(BackupTimestamp.string()).png", allowedTypes: [.png]) { url in
            guard let url else { return }
            do {
                try png.write(to: url)
                MacToastCenter.show("已导出图片 \(rows.count) 行")
            } catch {
                MacToastCenter.show("导出图片失败：\(error.localizedDescription)")
            }
        }
    }
}
