import Foundation

// MARK: - ZipStore：无需第三方库的「目录打包/解包」（用系统 /usr/bin/zip 与 ditto）
// 生成标准 zip，备份文件可被 Finder/系统直接打开，云端备份与 iOS 版互通。

enum ZipError: LocalizedError {
    case createFailed(String)
    case extractFailed(String)
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .createFailed(let m): return "打包失败：\(m)"
        case .extractFailed(let m): return "解包失败：\(m)"
        case .invalidPath: return "路径无效"
        }
    }
}

enum ZipStore {

    /// 打包目录/文件为 zip（zip -r -X）
    @discardableResult
    static func zip(items: [URL], to zipURL: URL, basePath: URL? = nil) -> Result<Void, Error> {
        try? FileManager.default.removeItem(at: zipURL)
        for item in items {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", "-X", zipURL.path, item.lastPathComponent]
            if let base = basePath {
                process.currentDirectoryURL = base
            } else {
                process.currentDirectoryURL = item.deletingLastPathComponent()
            }
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 { return .failure(ZipError.createFailed("zip 退出码 \(process.terminationStatus)")) }
            } catch {
                return .failure(ZipError.createFailed(error.localizedDescription))
            }
        }
        return .success(())
    }

    /// 打包单个目录为 zip
    @discardableResult
    static func zipDirectory(_ dir: URL, to zipURL: URL) -> Result<Void, Error> {
        try? FileManager.default.removeItem(at: zipURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-X", zipURL.path, dir.lastPathComponent]
        process.currentDirectoryURL = dir.deletingLastPathComponent()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 { return .failure(ZipError.createFailed("zip 退出码 \(process.terminationStatus)")) }
            return .success(())
        } catch {
            return .failure(ZipError.createFailed(error.localizedDescription))
        }
    }

    /// 解包 zip 到目标目录（ditto -x -k）
    @discardableResult
    static func unzip(_ zipURL: URL, to destDir: URL) -> Result<Void, Error> {
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destDir.path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 { return .failure(ZipError.extractFailed("ditto 退出码 \(process.terminationStatus)")) }
            return .success(())
        } catch {
            return .failure(ZipError.extractFailed(error.localizedDescription))
        }
    }
}
