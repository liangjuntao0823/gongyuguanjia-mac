import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 房源批量导入（对齐 iOS HouseBatchImportView v1.58/v1.59/v1.69）
// 三入口：CSV 清单 / zip 媒体包 / 扫描 media 补录；无前缀房号标红跳过（v1.69 规则）

struct BatchImportItem: Identifiable {
    let id = UUID()
    var roomNo: String
    var tower: Int
    var landlord: String
    var layout: String
    var price: Int
    var password: String
    var remark: String
    var status: String
    var duplicate: Bool = false
    var invalid: Bool = false      // 无 1-/2- 前缀 → 不符合规范
}

struct BatchImportSummary {
    var imported = 0
    var skipped = 0
    var failed = 0
}

struct HouseBatchImportView: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var mode = 0            // 0=清单 1=媒体包 2=扫描补录
    @State private var items: [BatchImportItem] = []
    @State private var errorMessage = ""
    @State private var importMessage = ""
    @State private var imported = false
    @State private var mediaSourceDir: URL? = nil   // zip 解压目录（nil = 本机 media 目录）

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("批量导入房源").font(.system(size: 18, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            .background(Color.themeHeader)
            Divider()

            // 模式选择（对齐 iOS BatchImportMode）
            Picker("导入方式", selection: $mode) {
                Text("清单导入（CSV/Excel）").tag(0)
                Text("媒体包导入（zip）").tag(1)
                Text("扫描补录（media 目录）").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14).padding(.top, 10)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 14))
                    .foregroundColor(.themeDanger)
                    .padding(.horizontal, 14).padding(.top, 8)
            }

            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 40)).foregroundColor(.gray)
                    switch mode {
                    case 0:
                        Text("选择一个 CSV/Excel 文件，列依次为：房号、房东、户型、租金（元）、密码、备注、状态")
                            .font(.system(size: 14))
                            .foregroundColor(.themeText3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Text("房号必须以 1- 或 2- 前缀开头（如 1-2334上）；无前缀行将标红跳过")
                            .font(.system(size: 13))
                            .foregroundColor(.themeDanger)
                    case 1:
                        Text("选择 iOS 导出的媒体包 zip：根目录为房号目录（如 1-2334上/），无记录自动建房源，已有记录自动补媒体")
                            .font(.system(size: 14))
                            .foregroundColor(.themeText3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    default:
                        Text("扫描本机 media 目录：与已收录房源比对，缺失的自动建房源，已有的自动补挂媒体关系（不复制文件）")
                            .font(.system(size: 14))
                            .foregroundColor(.themeText3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    HStack(spacing: 10) {
                        switch mode {
                        case 0:
                            Button("选择 CSV / Excel 文件") { pickFile() }.macSecondaryButton()
                        case 1:
                            Button("选择媒体包 zip") { pickZip() }.macSecondaryButton()
                        default:
                            Button("扫描并生成预览") { scanMedia() }.macSecondaryButton()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 10) {
                        Text("\(item.tower == 2 ? "2-" : (item.tower == 1 ? "1-" : ""))\(item.roomNo)")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 100, alignment: .leading)
                        Text(item.landlord).font(.system(size: 14)).frame(width: 70, alignment: .leading)
                        Text(item.layout).font(.system(size: 14)).frame(width: 60, alignment: .leading)
                        Text(item.price > 0 ? "¥\(item.price)" : "-").font(.system(size: 14)).frame(width: 60, alignment: .leading)
                        Text(item.status).font(.system(size: 14)).frame(width: 40, alignment: .leading)
                        Spacer()
                        if item.invalid {
                            Text("不符合规范")
                                .font(.system(size: 13))
                                .foregroundColor(.themeDanger)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(ThemeManager.isDark ? Color(red: 0.30, green: 0.16, blue: 0.16) : Color(hex: "FFEBEE"))
                                .clipShape(Capsule())
                        } else if item.duplicate {
                            Text("重复跳过")
                                .font(.system(size: 13))
                                .foregroundColor(.themeWarning)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(ThemeManager.isDark ? Color(red: 0.30, green: 0.26, blue: 0.15) : Color(hex: "FFF3E0"))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
                if !importMessage.isEmpty {
                    Text(importMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.themeAccent)
                        .padding(.horizontal, 14).padding(.bottom, 6)
                }
                HStack {
                    let invalidCount = items.filter(\.invalid).count
                    let dupCount = items.filter(\.duplicate).count
                    Text("共解析 \(items.count) 间：不符合规范 \(invalidCount) 间 · 重复 \(dupCount) 间，将跳过")
                        .font(.system(size: 13))
                        .foregroundColor(.themeText3)
                    Spacer()
                    Button("重新选择") { items = []; imported = false }.macSecondaryButton()
                    Button(imported ? "完成" : "开始导入") {
                        if imported { onClose() } else { runImport() }
                    }
                    .macPrimaryButton()
                    .disabled(items.isEmpty)
                }
                .padding(12)
            }
        }
        .frame(width: 640, height: 520)
    }

    // MARK: 入口 1 —— CSV 清单

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
        if lines.first!.contains("房号") || lines.first!.contains("房间") {
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
            let price = cols.count > 0 ? Int((Double(cols.removeFirst().replacingOccurrences(of: ",", with: "")) ?? 0).rounded()) : 0
            let password = cols.count > 0 ? cols.removeFirst() : ""
            let remark = cols.count > 0 ? cols.removeFirst() : ""
            let status = cols.count > 0 ? cols.removeFirst() : "待租"
            var item = BatchImportItem(roomNo: roomNo, tower: tower, landlord: landlord, layout: layout,
                                       price: price, password: password, remark: remark,
                                       status: status.contains("租") ? "已租" : "待租")
            item.invalid = !rawRoom.trimmingCharacters(in: .whitespaces).hasPrefix("1-") && !rawRoom.trimmingCharacters(in: .whitespaces).hasPrefix("2-")
            item.duplicate = Self.findDuplicate(roomNo: roomNo, tower: tower, in: manager.houses) != nil
            newItems.append(item)
        }
        items = newItems
        if items.isEmpty { errorMessage = "没有解析出任何房源行" }
    }

    // MARK: 入口 2 —— zip 媒体包

    private func pickZip() {
        MacBridge.openFiles(allowedTypes: [.zip, .data], allowsMultiple: false) { urls in
            guard let url = urls.first else { return }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("zip_import_\(UUID().uuidString)", isDirectory: true)
            if case .failure(let e) = ZipStore.unzip(url, to: dest) {
                errorMessage = "解压失败：\(e.localizedDescription)"
                return
            }
            buildFromMediaDir(dest)
        }
    }

    /// 从媒体目录构建房源清单（zip 解压目录 或 media 目录共用）
    private func buildFromMediaDir(_ dir: URL) {
        mediaSourceDir = dir
        errorMessage = ""
        guard let subDirs = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                         includingPropertiesForKeys: nil,
                                                                         options: [.skipsHiddenFiles]) else {
            errorMessage = "无法读取目录"
            return
        }
        var newItems: [BatchImportItem] = []
        for sub in subDirs where sub.hasDirectoryPath {
            let name = sub.lastPathComponent
            // 房号目录（1-2334上 / 2-1418下 或历史无前缀）
            let (roomNo, tower) = Self.parseRoom(name, explicitTower: 0)
            let mediaNames = (try? FileManager.default.contentsOfDirectory(atPath: sub.path))?.sorted() ?? []
            var item = BatchImportItem(roomNo: roomNo, tower: tower, landlord: "", layout: "",
                                       price: 0, password: "", remark: "来自媒体包（\(mediaNames.count) 个文件）", status: "待租")
            item.invalid = !name.hasPrefix("1-") && !name.hasPrefix("2-")
            item.duplicate = Self.findDuplicate(roomNo: roomNo, tower: tower, in: manager.houses) != nil
            newItems.append(item)
        }
        items = newItems
        if items.isEmpty { errorMessage = "压缩包内未找到房号目录（如 1-2334上/）" }
    }

    // MARK: 入口 3 —— 扫描 media 目录补录

    private func scanMedia() {
        let dir = DataRoot.mediaDirectory
        buildFromMediaDir(dir)
        if items.isEmpty { errorMessage = "media 目录为空或未找到房号目录" }
    }

    // MARK: 执行导入

    private func runImport() {
        var summary = BatchImportSummary()
        // zip 媒体包模式：先把房号目录复制进本机 media 目录（合并），再建房源/挂关系
        if mode == 1, let srcDir = mediaSourceDir {
            for item in items where !item.invalid {
                let roomKey = "\(item.tower)-\(item.roomNo)"
                let from = srcDir.appendingPathComponent(roomKey)
                let to = DataRoot.mediaDirectory.appendingPathComponent(roomKey)
                if FileManager.default.fileExists(atPath: from.path) {
                    try? FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
                    if let names = try? FileManager.default.contentsOfDirectory(atPath: from.path) {
                        for name in names {
                            let dest = to.appendingPathComponent(name)
                            if !FileManager.default.fileExists(atPath: dest.path) {
                                try? FileManager.default.copyItem(at: from.appendingPathComponent(name), to: dest)
                            }
                        }
                    }
                }
            }
        }
        for item in items {
            if item.invalid { summary.failed += 1; continue }
            if item.duplicate {
                // 重复但目录里可能有新媒体 → 补挂媒体关系（不重复建房源）
                if let existing = Self.findDuplicate(roomNo: item.roomNo, tower: item.tower, in: manager.houses) {
                    attachMissingMedia(from: "\(item.tower)-\(item.roomNo)", to: existing)
                }
                summary.skipped += 1
                continue
            }
            _ = manager.addHouse(roomNo: item.roomNo, tower: item.tower, landlord: item.landlord,
                                 layout: item.layout, price: item.price, password: item.password,
                                 remark: item.remark, status: item.status)
            summary.imported += 1
        }
        imported = true
        importMessage = "导入完成：新增 \(summary.imported) 间，跳过重复 \(summary.skipped) 间，不符合规范跳过 \(summary.failed) 间"
        MacToastCenter.show("已导入 \(summary.imported) 间房源")
    }

    /// 把媒体目录（zip 解压/media 扫描）里已有文件挂到本地房源（不重复复制，直接挂关系）
    private func attachMissingMedia(from roomKey: String, to house: House) {
        let src = DataRoot.mediaDirectory.appendingPathComponent(roomKey)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: src.path) else { return }
        let existing = Set(house.mediaItems.map { $0.fileName })
        for name in names where !existing.contains(name) {
            let lower = name.lowercased()
            let kind = lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v") ? "video" : "image"
            house.mediaItems.append(MediaItem(fileName: name, kind: kind))
        }
        try? manager.houseContext.save()
    }

    /// 房号解析：剥离「2- / 1-」前缀（2- 前缀 → 2座、1- 前缀 → 1座；无前缀默认 1 座并标 invalid）
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
