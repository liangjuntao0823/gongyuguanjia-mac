import Foundation

// MARK: - 房源媒体上传队列（新增/编辑房源后异步批量上传，失败保留可重试）

actor HouseMediaUploadQueue {

    static let shared = HouseMediaUploadQueue()

    private var isUploading = false
    private var pending: [(roomKey: String, fileName: String, kind: String)] = []
    private var failed: [(roomKey: String, fileName: String, kind: String)] = []

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

    // MARK: 失败保留（待补传媒体）

    func failedItems() -> [QueueItem] {
        failed.map { QueueItem(roomKey: $0.roomKey, fileName: $0.fileName, kind: $0.kind) }
    }

    func failedCount() -> Int { failed.count }

    /// 重试全部失败任务
    func retryAllFailed() {
        for item in failed { pending.append((item.roomKey, item.fileName, item.kind)) }
        failed.removeAll()
        Task { await drainIfNeeded() }
    }

    private func drainIfNeeded() async {
        guard !isUploading, !pending.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }

        guard let config = CosConfig.load() else {
            // 未配置云端：全部转失败保留，等待配置后重试
            failed.append(contentsOf: pending)
            pending.removeAll()
            return
        }
        while !pending.isEmpty {
            let task = pending.removeFirst()
            do {
                try await CosUploader.uploadHouseMedia(
                    fileName: task.fileName, kind: task.kind,
                    roomKey: task.roomKey, config: config,
                    compress: MediaSettingsStore.compressUpload
                )
            } catch {
                // 失败保留到待补传媒体，可手动重试（与 iOS 版一致）
                failed.append(task)
                CrashLogCollector.record("媒体上传失败", detail: "\(task.roomKey)/\(task.fileName): \(error.localizedDescription)")
            }
        }
        // 上传完成通知
        await MainActor.run {
            NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        }
    }
}
