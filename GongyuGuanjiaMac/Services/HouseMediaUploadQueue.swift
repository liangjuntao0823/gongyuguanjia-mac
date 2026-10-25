import Foundation

// MARK: - 房源媒体上传队列（新增/编辑房源后异步批量上传，失败可重试）

actor HouseMediaUploadQueue {

    static let shared = HouseMediaUploadQueue()

    private var isUploading = false
    private var pending: [(roomKey: String, fileName: String, kind: String)] = []

    struct QueueItem {
        let roomKey: String
        let fileName: String
        let kind: String
    }

    /// 入队：新增/编辑房源时调用
    func enqueue(roomKey: String, fileName: String, kind: String) {
        pending.append((roomKey, fileName, kind))
        Task { await drainIfNeeded() }
    }

    func enqueueBatch(_ tasks: [QueueItem]) {
        for t in tasks { pending.append((t.roomKey, t.fileName, t.kind)) }
        Task { await drainIfNeeded() }
    }

    func pendingCount() -> Int { pending.count }

    private func drainIfNeeded() async {
        guard !isUploading, !pending.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }

        guard let config = CosConfig.load() else { return }
        while !pending.isEmpty {
            let task = pending.removeFirst()
            do {
                try await CosUploader.uploadHouseMedia(
                    fileName: task.fileName, kind: task.kind,
                    roomKey: task.roomKey, config: config,
                    compress: MediaSettingsStore.compressUpload
                )
            } catch {
                CrashLogCollector.record("媒体上传失败", detail: "\(task.roomKey)/\(task.fileName): \(error.localizedDescription)")
            }
        }
        // 上传完成通知
        await MainActor.run {
            NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        }
    }
}
