import Foundation
import AppKit

// MARK: - 崩溃日志收集（写入 Logs/ 目录，随快速备份携带可排查）

enum CrashLogCollector {

    static func record(_ message: String, detail: String = "") {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(df.string(from: Date()))] \(message) \(detail)\n"
        let url = DataRoot.logsDirectory.appendingPathComponent("crash.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }

    /// 记录一般操作日志
    static func log(_ message: String) {
        record(message)
    }

    static func logsText() -> String {
        let url = DataRoot.logsDirectory.appendingPathComponent("crash.log")
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return "暂无日志" }
        return String(text.suffix(60000))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: DataRoot.logsDirectory.appendingPathComponent("crash.log"))
    }
}
