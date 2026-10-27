import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - 房源详情（媒体墙 + 信息 + 分享操作）
// macOS 标准：带明确关闭按钮的 sheet

struct HouseDetailView: View {
    @ObservedObject var manager: DataManager
    @Bindable var house: House
    let onClose: () -> Void

    @State private var showEdit = false
    @State private var showShareMenu = false
    @State private var sharing = false
    @State private var shareMessage = ""
    @State private var showSaveConfirm = false

    private var videos: [MediaItem] { house.mediaItems.filter { $0.kind == "video" } }
    private var images: [MediaItem] { house.mediaItems.filter { $0.kind == "image" } }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏（关闭按钮）
            HStack {
                Text("房源详情")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }
                    .macSecondaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 信息卡
                    HStack(alignment: .top, spacing: 16) {
                        MediaThumbView(house: house, size: 120)
                            .cornerRadius(10)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(house.displayRoomNo)
                                    .font(.system(size: 23, weight: .bold))
                                StatusBadge(status: house.status)
                                Text(house.towerLabel)
                                    .font(.system(size: 14))
                                    .foregroundColor(.themeText3)
                            }
                            Text("户型：\(house.layout)")
                                .font(.system(size: 16))
                            Text("租金：¥\(house.price) / 月")
                                .font(.system(size: 16))
                                .foregroundColor(.themeDanger)
                            Text("房东：\(house.landlord)")
                                .font(.system(size: 16))
                            if !house.password.isEmpty {
                                Text("门锁密码：\(house.password)")
                                    .font(.system(size: 16))
                            }
                            if !house.remark.isEmpty {
                                Text("备注：\(house.remark)")
                                    .font(.system(size: 15))
                                    .foregroundColor(.themeText2)
                            }
                            Text(house.photoSummary)
                                .font(.system(size: 14))
                                .foregroundColor(.themeText3)
                        }
                        Spacer()

                        // 操作按钮
                        VStack(alignment: .trailing, spacing: 8) {
                            Button {
                                showEdit = true
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .macSecondaryButton()

                            Button {
                                showShareMenu = true
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                            .macPrimaryButton()

                            Button {
                                softDelete()
                            } label: {
                                Label("下架/删除", systemImage: "trash")
                            }
                            .macSecondaryButton()
                        }
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    // 媒体区
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("实拍媒体（\(house.mediaItems.count)）")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Button {
                                addMedia()
                            } label: {
                                Label("添加图片/视频", systemImage: "plus")
                            }
                            .macSecondaryButton()
                        }

                        if house.mediaItems.isEmpty {
                            Text("暂无媒体，点击右上「添加图片/视频」上传实拍图")
                                .font(.system(size: 15))
                                .foregroundColor(.themeText3)
                                .padding(.vertical, 20)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 10)], spacing: 10) {
                                ForEach(house.mediaItems) { item in
                                    MediaItemCell(house: house, item: item) {
                                        removeMedia(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    // 分享结果提示
                    if sharing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在生成分享链接…")
                                .font(.system(size: 15))
                        }
                        .padding(.vertical, 6)
                    }
                    if !shareMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: shareMessage.contains("失败") ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(shareMessage.contains("失败") ? .themeDanger : .themeAccent)
                            Text(shareMessage)
                                .font(.system(size: 15))
                            Spacer()
                            if shareMessage.contains("链接") && !shareMessage.contains("失败") {
                                Button("复制链接") {
                                    MacBridge.copy(shareMessage.replacingOccurrences(of: "已生成分享链接：", with: ""))
                                    MacToastCenter.show("链接已复制")
                                }
                                .macSecondaryButton()
                            }
                        }
                        .padding(10)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .frame(width: 760, height: 640)
        .background(Color.themeBg)
        .sheet(isPresented: $showEdit) {
            HouseEditView(manager: manager, house: house) {
                showEdit = false
            }
        }
        .sheet(isPresented: $showShareMenu) {
            ShareMenuView(manager: manager, house: house) {
                showShareMenu = false
            }
        }
        .alert("已保存图片", isPresented: $showSaveConfirm) {
            Button("好", role: .cancel) {}
        }
    }

    private func removeMedia(_ item: MediaItem) {
        manager.removeMedia(item, from: house)
        MacToastCenter.show("已删除该媒体")
    }

    private func addMedia() {
        MacBridge.openFiles(allowedTypes: [.image, .movie], allowsMultiple: true) { urls in
            for url in urls {
                let ext = url.pathExtension.lowercased()
                let kind: String
                if ["mp4", "mov", "m4v"].contains(ext) {
                    kind = "video"
                } else {
                    kind = "image"
                }
                manager.addMedia(to: house, url: url, kind: kind)
            }
            if !urls.isEmpty {
                MacToastCenter.show("已添加 \(urls.count) 个媒体")
            }
        }
    }

    private func softDelete() {
        manager.softDeleteHouse(house)
        MacToastCenter.show("房源已下架，可在回收站恢复")
        onClose()
    }
}

// MARK: - 单个媒体单元

struct MediaItemCell: View {
    let house: House
    let item: MediaItem
    let onDelete: () -> Void

    @State private var showImage = false
    @State private var nsImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if item.kind == "image" {
                    if let img = loadImage() {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 110)
                            .clipped()
                            .onTapGesture {
                                nsImage = img
                                showImage = true
                            }
                    } else {
                        Color.gray.opacity(0.2)
                            .frame(height: 110)
                    }
                } else {
                    ZStack {
                        Color.black.opacity(0.85)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.white)
                    }
                    .frame(height: 110)
                    .onTapGesture {
                        openVideo()
                    }
                }
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
            }
            Text(item.fileName)
                .font(.system(size: 10))
                .foregroundColor(.themeText3)
                .lineLimit(1)
                .padding(4)
        }
        .background(Color.white)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder))
        .sheet(isPresented: $showImage) {
            if let nsImage = nsImage {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showImage = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 23))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }
                    Spacer()
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                    Spacer()
                }
                .frame(width: 720, height: 560)
                .background(Color.black.opacity(0.95))
            }
        }
    }

    private func loadImage() -> NSImage? {
        let url = MediaStore.fileURL(fileName: item.fileName, roomKey: house.mediaRoomKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func openVideo() {
        let url = MediaStore.fileURL(fileName: item.fileName, roomKey: house.mediaRoomKey)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            MacToastCenter.show("本地视频不存在，请先云端同步")
        }
    }
}

// MARK: - 分享菜单

struct ShareMenuView: View {
    @ObservedObject var manager: DataManager
    let house: House
    let onClose: () -> Void

    @State private var mode: ShareMode = .masked
    @State private var working = false
    @State private var resultMessage = ""
    @State private var resultLink = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("分享房源 \(house.displayRoomNo)")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Picker("分享模式", selection: $mode) {
                Text("脱敏版（隐藏密码/价格）").tag(ShareMode.masked)
                Text("完整版（含密码/房东信息）").tag(ShareMode.full)
            }
            .pickerStyle(.radioGroup)

            Text("脱敏版适合发给租客初步挑选；完整版适合已确定意向的租客。")
                .font(.system(size: 13))
                .foregroundColor(.themeText3)

            if working {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在生成 H5 页面并上传云端…")
                        .font(.system(size: 15))
                }
            }

            if !resultMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(resultMessage)
                        .font(.system(size: 15))
                        .foregroundColor(resultMessage.contains("失败") ? .themeDanger : .themeAccent)
                    if !resultLink.isEmpty {
                        HStack(spacing: 8) {
                            Button("复制链接") {
                                MacBridge.copy(resultLink)
                                MacToastCenter.show("链接已复制")
                            }
                            .macPrimaryButton()
                            Button("分享…") {
                                shareLink()
                            }
                            .macSecondaryButton()
                            Button("浏览器打开") {
                                MacBridge.openURL(resultLink)
                            }
                            .macSecondaryButton()
                        }
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)
            }

            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .macSecondaryButton()
                Button("生成分享链接") { generate() }
                    .macPrimaryButton()
                    .disabled(working)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            resultMessage = ""
            // v1.2.4：详情页打开自动补缺缺失媒体（对齐 iOS v1.43 详情页补缺）
            if let config = CosConfig.load(), config.isValid {
                Task { await CloudHouseSync.downloadMissingMedia(house: house, config: config) }
            }
        }
    }

    private func generate() {
        guard CosConfig.load() != nil else {
            resultMessage = "未配置云端，请先到设置完成云配置"
            return
        }
        guard !house.mediaItems.isEmpty else {
            resultMessage = "该房源还没有实拍图/视频，先添加媒体再分享"
            return
        }
        working = true
        resultMessage = ""
        let info = manager.shareInfo(for: house)
        let mediaFiles = house.mediaItems.map { ShareMediaFile(name: $0.fileName, kind: $0.kind) }
        Task {
            do {
                let link = try await CosUploader.shareCard(
                    mediaFiles: mediaFiles, roomKey: house.mediaRoomKey,
                    info: info, mode: mode, config: CosConfig.load()!
                )
                resultMessage = "已生成分享链接：\(link)"
                resultLink = link
                BackupLogStore.log("分享\(mode.modeLabel)", detail: "\(house.displayRoomNo)", kind: "local")
            } catch {
                resultMessage = "生成失败：\(error.localizedDescription)"
                resultLink = ""
            }
            working = false
        }
    }

    private func shareLink() {
        guard !resultLink.isEmpty else { return }
        MacBridge.share(items: [URL(string: resultLink)!], from: nil)
    }
}
