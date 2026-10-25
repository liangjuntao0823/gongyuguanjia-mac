import Foundation

// MARK: - 房源媒体本地存储（与 iOS 版一致：DataRoot/media/<roomKey>/<fileName>）

enum MediaStore {

    static func mediaDirectory() -> URL { DataRoot.mediaDirectory }

    /// 房源媒体目录（不存在则创建）
    static func roomDirectory(roomKey: String) -> URL {
        let dir = mediaDirectory().appendingPathComponent(roomKey, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(fileName: String, roomKey: String? = nil) -> URL {
        if let roomKey = roomKey {
            return roomDirectory(roomKey: roomKey).appendingPathComponent(fileName)
        }
        // 兼容旧调用：直接在媒体根目录
        return mediaDirectory().appendingPathComponent(fileName)
    }

    static func fileURL(fileName: String) -> URL {
        mediaDirectory().appendingPathComponent(fileName)
    }

    /// 保存媒体文件到房源目录
    @discardableResult
    static func save(data: Data, fileName: String, roomKey: String) -> URL? {
        let dir = roomDirectory(roomKey: roomKey)
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch { return nil }
    }

    /// 列出房源目录内媒体文件名（按名字排序，视频优先由上层处理）
    static func mediaNames(roomKey: String) -> [String] {
        let dir = roomDirectory(roomKey: roomKey)
        return (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.sorted() ?? []
    }

    /// 房源目录大小（备份统计用）
    static func roomSize(roomKey: String) -> Int64 {
        let dir = roomDirectory(roomKey: roomKey)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var total: Int64 = 0
        for f in files {
            let p = dir.appendingPathComponent(f)
            if let attr = try? FileManager.default.attributesOfItem(atPath: p.path) {
                total += (attr[.size] as? Int64) ?? 0
            }
        }
        return total
    }

    /// 删除房源媒体目录
    static func removeRoom(roomKey: String) {
        let dir = roomDirectory(roomKey: roomKey)
        try? FileManager.default.removeItem(at: dir)
    }

    /// 删除单个媒体文件
    static func removeMedia(fileName: String, roomKey: String) {
        let url = roomDirectory(roomKey: roomKey).appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// 全部媒体总大小
    static func totalSize() -> Int64 {
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: mediaDirectory().path) else { return 0 }
        var total: Int64 = 0
        for d in dirs {
            var isDir: ObjCBool = false
            let p = mediaDirectory().appendingPathComponent(d)
            if FileManager.default.fileExists(atPath: p.path, isDirectory: &isDir), isDir.boolValue {
                total += roomSize(roomKey: d)
            }
        }
        return total
    }
}
