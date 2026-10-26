import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 房源批量导入（对齐 iOS HouseBatchImportView：CSV 解析 + 预览 + 重复跳过）

struct BatchImportItem: Identifiable {
    let id = UUID()
    var roomNo: String
    var tower: Int
    var landlord: String
    var layout: String
    var price: Double
    var password: String
    var remark: String
    var status: String
    var duplicate: Bool = false
}

struct BatchImportSummary {
    var imported = 0
    var skipped = 0
    var failed = 0
}

struct HouseBatchImportView: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var items: [BatchImportItem] = []
    @State private var errorMessage = ""
    @State private var importMessage = ""
    @State private var imported = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("批量导入房源").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("选择 CSV / Excel 文件") { pickFile() }.macSecondaryButton()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.themeDanger)
                    .padding(.horizontal, 14).padding(.top, 8)
            }

            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 40)).foregroundColor(.gray)
                    Text("选择一个 CSV/Excel 文件，列依次为：房号、房东、户型、租金（元）、密码、备注、状态")
                        .font(.system(size: 13))
                        .foregroundColor(.themeText3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Text("房号带「2-」前缀 → 2座；首行含“房号/房间”等表头会自动跳过")
                        .font(.system(size: 12))
                        .foregroundColor(.themeText3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 10) {
                        Text("\(item.tower == 2 ? "2-" : "")\(item.roomNo)")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 90, alignment: .leading)
                        Text(item.landlord).font(.system(size: 13)).frame(width: 70, alignment: .leading)
                        Text(item.layout).font(.system(size: 13)).frame(width: 60, alignment: .leading)
                        Text("¥\(Int(item.price))").font(.system(size: 13)).frame(width: 60, alignment: .leading)
                        Text(item.status).font(.system(size: 13)).frame(width: 40, alignment: .leading)
                        Spacer()
                        if item.duplicate {
                            Text("重复跳过")
                                .font(.system(size: 12))
                                .foregroundColor(.themeWarning)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color(hex: "FFF3E0"))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
                if !importMessage.isEmpty {
                    Text(importMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.themeAccent)
                        .padding(.horizontal, 14).padding(.bottom, 6)
                }
                HStack {
                    Text("共解析 \(items.count) 间，其中重复 \(items.filter(\.duplicate).count) 间将跳过")
                        .font(.system(size: 12))
                        .foregroundColor(.themeText3)
                    Spacer()
                    Button("重新选择文件") { items = []; imported = false }.macSecondaryButton()
                    Button(imported ? "完成" : "开始导入") {
                        if imported { onClose() } else { runImport() }
                    }
                    .macPrimaryButton()
                    .disabled(items.isEmpty)
                }
                .padding(12)
            }
        }
        .frame(width: 620, height: 500)
    }

    private func pickFile() {
        MacBridge.openFiles(allowedTypes: [.spreadsheet, .commaSeparatedText, .plainText, .data], allowsMultiple: false) { urls in
            guard let url = urls.first else { return }
            guard let data = try? Data(contentsOf: url) else { errorMessage = "无法读取文件"; return }
            var text: String?
            for enc in [String.Encoding.utf8, .utf16, String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))] {
                if let s = String(data: data, encoding: enc) { text = s; break }
            }
            guard let csv = text else { errorMessage = "无法识别文件编码（请使用 UTF-8/GBK）"; return }
            parse(csv)
        }
    }

    /// CSV 解析：忽略表头（首行含「房号/房间」关键字跳过），兼容中文逗号/制表符/引号
    private func parse(_ raw: String) {
        items = []
        errorMessage = ""
        let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { errorMessage = "文件内容为空或只有一行"; return }
        var startIndex = 0
        if lines.first!.contains("房号") || lines.first!.contains("房间") || lines.first!.contains("房号") {
            startIndex = 1
        }
        var newItems: [BatchImportItem] = []
        for line in lines[startIndex...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var cols = trimmed.components(separatedBy: CharacterSet(charactersIn: ",\t，"))
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
                .filter { !$0.isEmpty }
            if cols.isEmpty { continue }
            let rawRoom = cols.removeFirst()
            let (roomNo, tower) = Self.parseRoom(rawRoom, explicitTower: 0)
            let landlord = cols.count > 0 ? cols.removeFirst() : ""
            let layout = cols.count > 0 ? cols.removeFirst() : ""
            let price = cols.count > 0 ? Double(cols.removeFirst().replacingOccurrences(of: ",", with: "")) ?? 0 : 0
            let password = cols.count > 0 ? cols.removeFirst() : ""
            let remark = cols.count > 0 ? cols.removeFirst() : ""
            let status = cols.count > 0 ? cols.removeFirst() : "待租"
            var item = BatchImportItem(roomNo: roomNo, tower: tower, landlord: landlord, layout: layout,
                                       price: price, password: password, remark: remark,
                                       status: status.contains("租") ? "已租" : "待租")
            item.duplicate = Self.findDuplicate(roomNo: roomNo, tower: tower, in: manager.houses) != nil
            newItems.append(item)
        }
        items = newItems
        if items.isEmpty { errorMessage = "没有解析出任何房源行" }
    }

    private func runImport() {
        var summary = BatchImportSummary()
        for item in items {
            if item.duplicate {
                summary.skipped += 1
                continue
            }
            _ = manager.addHouse(roomNo: item.roomNo, tower: item.tower, landlord: item.landlord,
                                 layout: item.layout, price: item.price, password: item.password,
                                 remark: item.remark, status: item.status)
            summary.imported += 1
        }
        imported = true
        importMessage = "导入完成：新增 \(summary.imported) 间，跳过重复 \(summary.skipped) 间，失败 \(summary.failed) 间"
        MacToastCenter.show("已导入 \(summary.imported) 间房源")
    }

    /// 房号解析：剥离「2- / 1-」前缀（2- 前缀 → 2座）
    static func parseRoom(_ raw: String, explicitTower: Int) -> (String, Int) {
        var room = raw.trimmingCharacters(in: .whitespaces)
        if room.hasPrefix("2-") { return (String(room.dropFirst(2)), 2) }
        if room.hasPrefix("1-") { return (String(room.dropFirst(2)), 1) }
        if explicitTower != 0 { return (room, explicitTower) }
        return (room, 1)
    }

    static func findDuplicate(roomNo: String, tower: Int, in all: [House]) -> House? {
        all.first { $0.isDeleted != true && $0.tower == tower && Self.normalized($0.roomNo) == Self.normalized(roomNo) }
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "-", with: "")
    }
}
