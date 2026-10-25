import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Excel 导入导出（与 iOS 版同机制：HTML 表格伪 .xls，纯字符串）
// 导出 .xls 可用 Excel/WPS 打开；导入支持 UTF-8/GBK 编码的 .xls/.csv

enum ExcelService {

    static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// 把二维数组导出为 HTML 伪 xls 数据
    static func makeExcelHTML(rows: [[String]], sheetName: String = "Sheet1") -> Data {
        let header = "<?xml version=\"1.0\"?><Workbook xmlns=\"urn:schemas-microsoft-com:office:spreadsheet\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:x=\"urn:schemas-microsoft-com:office:excel\" xmlns:ss=\"urn:schemas-microsoft-com:office:spreadsheet\" xmlns:html=\"http://www.w3.org/TR/REC-html40\"><Worksheet ss:Name=\"\(htmlEscape(sheetName))\"><Table>"
        var body = ""
        for row in rows {
            body += "<Row>"
            for cell in row {
                body += "<Cell><Data ss:Type=\"String\">\(htmlEscape(cell))</Data></Cell>"
            }
            body += "</Row>"
        }
        let footer = "</Table></Worksheet></Workbook>"
        return Data((header + body + footer).utf8)
    }

    /// 解析导入文件（HTML 表格 或 CSV）
    static func parseImported(_ data: Data) -> [[String]] {
        // 尝试 UTF-8
        var text = String(data: data, encoding: .utf8)
        if text == nil {
            // GBK 兜底
            text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
        }
        guard let t = text else { return [] }
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)

        // HTML 表格
        if trimmed.hasPrefix("<") || trimmed.contains("<Row>") || trimmed.contains("<Table>") {
            return parseHTMLTable(t)
        }
        // CSV
        return parseCSV(t)
    }

    private static func parseHTMLTable(_ html: String) -> [[String]] {
        var rows: [[String]] = []
        var rest = html[...]
        while let rowStart = rest.range(of: "<Row>"), let rowEnd = rest[rowStart.upperBound...].range(of: "</Row>") {
            let rowContent = String(rest[rowStart.upperBound..<rowEnd.lowerBound])
            var cells: [String] = []
            var cr = rowContent[...]
            while let cStart = cr.range(of: "<Cell>"), let cEnd = cr[cStart.upperBound...].range(of: "</Cell>") {
                let cellContent = String(cr[cStart.upperBound..<cEnd.lowerBound])
                if let dStart = cellContent.range(of: "<Data")?.upperBound,
                   let dMid = cellContent[dStart...].range(of: ">")?.lowerBound,
                   let dEnd = cellContent[dMid...].range(of: "</Data>")?.lowerBound {
                    cells.append(String(cellContent[dMid..<dEnd]).htmlDecoded)
                } else {
                    cells.append(cellContent.htmlDecoded)
                }
                cr = cr[cEnd.upperBound...]
            }
            rows.append(cells)
            rest = rest[rowEnd.upperBound...]
        }
        return rows
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case ",":
                    current.append(field)
                    field = ""
                case "\n":
                    current.append(field)
                    rows.append(current)
                    current = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(ch)
                }
            }
            i += 1
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        return rows
    }
}

extension String {
    var htmlDecoded: String {
        var s = self
        let replacements = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
            "&nbsp;": " ", "&nbsp": " "
        ]
        for (k, v) in replacements { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }
}
