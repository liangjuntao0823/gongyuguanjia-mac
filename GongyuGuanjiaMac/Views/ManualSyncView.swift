import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins
import Darwin

// MARK: - 手动同步（Mac 形态：状态展示 + 本机同步码二维码 + 云端同步引导）
// 对应 iOS ManualSyncView / MigrationView；Mac 无摄像头，扫码由 iOS 完成（展示二维码供 iOS 扫一扫）

struct ManualSyncView: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    @State private var pendingCount = 0
    @State private var conflictCount = 0
    @State private var hasSynced = false
    @State private var qrImage: NSImage?
    @State private var syncLink = ""
    @State private var hostIP = "127.0.0.1"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("手动同步").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }.macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 本机同步码（P1-6）：iOS 扫码从 Mac 拉取（Mac 无摄像头，扫码由 iOS 完成）
                    infoCard("本机同步码（供 iOS 扫码）") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let img = qrImage {
                                HStack(spacing: 14) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .interpolation(.none)
                                        .frame(width: 150, height: 150)
                                        .padding(8)
                                        .background(Color.white)
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder))
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("地址 \(hostIP):8765")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("iOS 端操作：「手动同步 → 扫一扫」扫此码即可从 Mac 拉取经营数据与房源。")
                                            .font(.system(size: 14))
                                            .foregroundColor(.themeText3)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack(spacing: 10) {
                                            Button("复制 zfgj 链接") { copySyncLink() }.macSecondaryButton()
                                            Button("刷新同步码") { makeSyncQR() }.macSecondaryButton()
                                        }
                                    }
                                    Spacer()
                                }
                            } else {
                                ProgressView().controlSize(.small)
                                Text("正在生成同步码…").font(.system(size: 14)).foregroundColor(.themeText3)
                            }
                        }
                    }
                    infoCard("本机同步状态") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("待上传变更：\(pendingCount) 条")
                            Text("未解决冲突：\(conflictCount) 条")
                            Text(hasSynced ? "已建立同步基线（后续可继续增量同步）" : "尚未进行过手动同步（或基线已清空）")
                                .foregroundColor(.themeText3)
                        }
                        .font(.system(size: 15))
                    }
                    infoCard("说明") {
                        Text("Mac 版已内置同步协议层（SyncCore / SyncDTO / SwiftDataSyncSnapshot），与 iOS 版同一套数据结构。由于 Mac 无摄像头扫码，局域网扫码同步改为云端同步通道：在「设置 → 云端同步」中配置同一用户名，即可与 iOS 双向同步房源与经营数据。")
                            .font(.system(size: 14))
                            .foregroundColor(.themeText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    infoCard("数据迁移（对应 iOS MigrationView）") {
                        Text("iOS 版的 zfgj 迁移文件在 Mac 端以备份文件形态实现：在「设置 → 备份与恢复 → 打开备份中心」中，用「恢复」选择备份文件即可完整迁移经营数据+房源字段；全量备份还含实拍照片/视频。")
                            .font(.system(size: 14))
                            .foregroundColor(.themeText3)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("打开备份中心") { onClose() }
                                .macSecondaryButton()
                            Button("去云端同步") { onClose() }
                                .macPrimaryButton()
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 480)
        .onAppear {
            Task {
                let snap = await SyncStore.shared.snapshot()
                pendingCount = snap.pending.count
                conflictCount = snap.conflicts.count
                hasSynced = snap.cursor != nil
            }
            makeSyncQR()
        }
    }

    // MARK: 同步码生成（局域网 IP + 6 位随机码 → zfgj:// 链接 → 二维码）

    private func makeSyncQR() {
        hostIP = Self.localIPAddress() ?? "127.0.0.1"
        let code = String(format: "%06d", Int.random(in: 0...999999))
        let info = SyncConnectionInfo(host: hostIP, port: 8765, code: code)
        syncLink = info.qrText
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(syncLink.utf8)
        if let output = filter.outputImage,
           let cg = context.createCGImage(output.transformed(by: CGAffineTransform(scaleX: 6, y: 6)), from: output.transformed(by: CGAffineTransform(scaleX: 6, y: 6)).extent) {
            qrImage = NSImage(cgImage: cg, size: NSSize(width: 150, height: 150))
        }
    }

    private func copySyncLink() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(syncLink, forType: .string)
        MacToastCenter.show("zfgj 链接已复制（iOS 端「手动同步 → 扫一扫」也可直接粘贴识别）")
    }

    /// 获取本机局域网 IP（与 iOS 端同步码同口径）
    private static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: host)
                    if address != "127.0.0.1" { break }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    private func infoCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .bold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themePanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
    }
}
