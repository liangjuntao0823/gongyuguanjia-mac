import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - iOS → macOS 桥接层（所有平台差异集中在这里，界面层只调用这些方法）

enum MacBridge {

    // MARK: 剪贴板

    /// 复制文本到剪贴板
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 复制并提示
    static func copyWithTip(_ text: String, tip: String) {
        copy(text)
        NotificationCenter.default.post(name: .macShowToast, object: nil, userInfo: ["text": tip])
    }

    // MARK: 打开链接 / 文件夹

    /// 用默认浏览器打开 URL
    static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 在 Finder 中显示目录
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: 保存文件（NSSavePanel）

    /// 弹出保存面板，返回用户选择的目标 URL（取消返回 nil）
    static func saveFile(defaultName: String, allowedTypes: [UTType], completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: 打开文件（NSOpenPanel）

    /// 弹出文件选择面板（单选/多选），返回用户选择的 URL 列表
    static func openFiles(allowedTypes: [UTType], allowsMultiple: Bool, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK {
                completion(panel.urls)
            } else {
                completion([])
            }
        }
    }

    /// 单选文件（便捷）
    static func openFile(allowedTypes: [UTType], completion: @escaping (URL?) -> Void) {
        openFiles(allowedTypes: allowedTypes, allowsMultiple: false) { urls in
            completion(urls.first)
        }
    }

    // MARK: 分享面板（NSSharingServicePicker）

    /// 分享链接/文本
    static func share(items: [Any], from view: NSView?) {
        let picker = NSSharingServicePicker(items: items)
        if let view = view {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let keyWindow = NSApp.keyWindow, let contentView = keyWindow.contentView {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }

    // MARK: 保存媒体到相册（macOS 无相册 → 存到「图片/公寓管家」）

    /// 保存图片数据到 ~/Pictures/公寓管家/，返回是否成功
    @discardableResult
    static func saveImageToPictures(_ data: Data, name: String) -> Bool {
        guard let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else { return false }
        let dir = pics.appendingPathComponent("公寓管家", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// 保存文件到 ~/Downloads（视频等）
    @discardableResult
    static func saveToDownloads(_ url: URL) -> Bool {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return false }
        let target = downloads.appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: url, to: target)
            return true
        } catch {
            return false
        }
    }

    // MARK: 系统信息

    static var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - Toast 通知（窗口顶部浮动提示）

struct MacToastCenter {
    static func show(_ text: String) {
        NotificationCenter.default.post(name: .macShowToast, object: nil, userInfo: ["text": text])
    }
}

extension Notification.Name {
    static let macShowToast = Notification.Name("macShowToast")
}

// MARK: - 视图修饰符：给窗口挂 Toast

struct MacToastModifier: ViewModifier {
    @State private var message: String?
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.themeBorder))
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(duration: 0.25), value: message)
            .onReceive(NotificationCenter.default.publisher(for: .macShowToast)) { note in
                let text = note.userInfo?["text"] as? String ?? ""
                task?.cancel()
                message = text
                task = Task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    if !Task.isCancelled {
                        withAnimation { message = nil }
                    }
                }
            }
    }
}

extension View {
    func macToast() -> some View { modifier(MacToastModifier()) }
}

// MARK: - 通用按钮样式

struct MacPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundColor(.white)
            .background(configuration.isPressed ? Color.themeAccent.opacity(0.8) : Color.themeAccent)
            .cornerRadius(7)
    }
}

struct MacSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundColor(.themeText)
            .background(configuration.isPressed ? Color.gray.opacity(0.18) : Color.gray.opacity(0.10))
            .cornerRadius(7)
    }
}

extension View {
    func macPrimaryButton() -> some View { buttonStyle(MacPrimaryButtonStyle()) }
    func macSecondaryButton() -> some View { buttonStyle(MacSecondaryButtonStyle()) }
}

// MARK: - 通用错误（Result 的 Failure 必须 conform Error）

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}
