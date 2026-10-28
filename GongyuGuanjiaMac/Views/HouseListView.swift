import SwiftUI
import SwiftData
import AppKit
import AVFoundation

// MARK: - 共享房源组件（缩略图 / 状态徽标）

/// 房源媒体缩略图：图片直接显示；视频显示首帧或播放图标
struct MediaThumbView: View {
    private let item: MediaItem?
    private let roomKey: String
    let size: CGFloat

    /// 以房源整体取首媒体（视频优先）
    init(house: House, size: CGFloat) {
        self.item = house.mediaItems.first { $0.kind == "video" } ?? house.mediaItems.first { $0.kind == "image" }
        self.roomKey = house.mediaRoomKey
        self.size = size
    }

    /// 指定单个媒体项（编辑页媒体管理用）
    init(item: MediaItem, roomKey: String, size: CGFloat) {
        self.item = item
        self.roomKey = roomKey
        self.size = size
    }

    @State private var videoThumb: NSImage?

    var body: some View {
        Group {
            if let item {
                if item.kind == "image", let nsImage = loadImage(item.fileName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // 视频：异步加载首帧缩略图（未加载完显示播放图标占位）
                    ZStack {
                        if let thumb = videoThumb {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.25)
                            Image(systemName: "video.fill")
                                .font(.system(size: size * 0.25))
                                .foregroundColor(.white)
                        }
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: size * 0.16))
                            .foregroundColor(.white.opacity(0.92))
                            .shadow(radius: 2)
                    }
                    .onAppear {
                        loadVideoThumb()
                    }
                    .highPriorityGesture(TapGesture().onEnded { openVideo() })
                }
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.87, green: 0.89, blue: 0.91), Color(red: 0.78, green: 0.80, blue: 0.84)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.22))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private func openVideo() {
        guard let item else { return }
        let url = MediaStore.fileURL(fileName: item.fileName, roomKey: roomKey)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            MacToastCenter.show("本地视频不存在，请先云端同步")
        }
    }

    private func loadVideoThumb() {
        guard let item, item.kind != "image" else { return }
        let cache = VideoThumbCache.load(roomKey: roomKey, fileName: item.fileName)
        DispatchQueue.main.async {
            if let cache { videoThumb = cache }
        }
    }

    private func loadImage(_ fileName: String) -> NSImage? {
        let url = MediaStore.fileURL(fileName: fileName, roomKey: roomKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(.white)
            .background(status == "待租" ? Color.themeAccent : Color.themeWarning)
            .cornerRadius(6)
    }
}

// MARK: - 房源列表

struct HouseListView: View {
    @ObservedObject var manager: DataManager

    @State private var searchText = ""
    @State private var towerFilter = "全部"
    @State private var statusFilter = "待租"   // v1.2.12：进入板块默认显示待租房源
    @State private var selectedLayouts: Set<String> = []
    @State private var viewMode = "网格"
    @State private var selectedHouse: House?
    @State private var editingHouse: House?
    @State private var sharingHouse: House?
    @State private var pendingDelete: House?
    @State private var showNew = false
    @State private var showTrash = false
    @State private var showBatchImport = false
    @State private var selecting = false          // 多选模式
    @State private var selectedKeys: Set<UUID> = []
    @State private var batchBusy = false
    @State private var collectionURL = ""
    @State private var syncing = false
    @State private var syncAlert: String?
    @State private var syncProgress: Double = 0
    @State private var syncStatus = ""
    @State private var localRefreshing = false
    @ObservedObject private var syncCenter = SyncTaskCenter.shared
    @State private var syncMinimized = false

    private var houses: [House] { manager.houses }

    private var layoutOptions: [String] {
        var set = Set<String>()
        for h in houses where h.isDeleted != true { set.insert(h.layout) }
        return ["全部户型"] + set.sorted()
    }

    private var filtered: [House] {
        houses.filter { h in
            guard h.isDeleted != true else { return false }
            if !searchText.isEmpty {
                let kw = searchText.lowercased()
                if !h.displayRoomNo.lowercased().contains(kw) && !h.landlord.lowercased().contains(kw) && !h.layout.lowercased().contains(kw) {
                    return false
                }
            }
            if towerFilter != "全部" && "\(h.tower)座" != towerFilter { return false }
            if statusFilter != "全部" && h.status != statusFilter { return false }
            if !selectedLayouts.isEmpty && !selectedLayouts.contains(h.layout) { return false }
            return true
        }
        .sorted {
            if $0.tower != $1.tower { return $0.tower < $1.tower }
            let a = Int($0.sortDigits) ?? 0, b = Int($1.sortDigits) ?? 0
            if a != b { return a < b }
            return $0.roomNo < $1.roomNo
        }
    }

    private var stats: DataManager.HouseStats { manager.houseStats(filtered) }

    private func confirmDelete(_ house: House) {
        pendingDelete = house
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("房源管理").font(.system(size: 20, weight: .bold))
                    Text("共 \(stats.total) 套 · 1座 \(stats.tower1) · 2座 \(stats.tower2) · 待租 \(stats.available) · 已租 \(stats.rented) · 实拍图 \(stats.withPhoto)/无 \(stats.withoutPhoto)")
                        .font(.system(size: 12)).foregroundColor(.themeText3)
                }
                Spacer()
                Button {
                    showBatchImport = true
                } label: {
                    Label("批量导入", systemImage: "square.and.arrow.down")
                }
                .macSecondaryButton()
                Button {
                    selecting.toggle()
                    if !selecting { selectedKeys.removeAll() }
                } label: {
                    Label(selecting ? "完成多选" : "多选", systemImage: selecting ? "checkmark.circle" : "checkmark.circle")
                }
                .macSecondaryButton()
                Button {
                    localRefreshWithMediaCheck()
                } label: {
                    Label(localRefreshing ? "检查中…" : "本地刷新", systemImage: "arrow.clockwise")
                }
                .macSecondaryButton()
                .disabled(localRefreshing || syncing)
                Button {
                    refreshSync()
                } label: {
                    Label(syncing ? "同步中…" : "云端同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .macSecondaryButton()
                .disabled(syncing)
                Button {
                    showNew = true
                } label: {
                    Label("新增房源", systemImage: "plus")
                }
                .macPrimaryButton()
                Button {
                    showTrash = true
                } label: {
                    Label("回收站", systemImage: "trash")
                }
                .macSecondaryButton()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // 同步任务进度条（对齐 iOS v1.68：全局同步任务中心，可最小化收起）
            if (syncing || localRefreshing) && !syncMinimized {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(localRefreshing ? "本地媒体检查…" : (syncStatus.isEmpty ? "正在同步…" : syncStatus))
                            .font(.system(size: 12))
                            .foregroundColor(.themeText2)
                        Spacer()
                        if syncing { Text("\(Int(syncProgress * 100))%").font(.system(size: 12)).foregroundColor(.themeText2) }
                        Button("收起") { withAnimation { syncMinimized = true } }
                            .macSecondaryButton()
                    }
                    ProgressView(value: syncing ? syncProgress : 0, total: 1.0)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            } else if (syncing || localRefreshing) && syncMinimized {
                // 最小化条：任务继续后台跑，随时可展开
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text(localRefreshing ? "本地媒体检查进行中…" : "同步任务进行中…")
                        .font(.system(size: 12)).foregroundColor(.themeText2)
                    Spacer()
                    Button("展开") { withAnimation { syncMinimized = false } }
                        .macSecondaryButton()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            // 筛选
            HStack(spacing: 10) {
                TextField("搜索房号 / 房东 / 户型", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Picker("", selection: $towerFilter) {
                    Text("全部座").tag("全部")
                    Text("1座").tag("1座")
                    Text("2座").tag("2座")
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                Picker("", selection: $statusFilter) {
                    Text("全部状态").tag("全部")
                    Text("待租").tag("待租")
                    Text("已租").tag("已租")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Menu {
                    ForEach(layoutOptions.filter { $0 != "全部户型" }, id: \.self) { opt in
                        Button {
                            if selectedLayouts.contains(opt) { selectedLayouts.remove(opt) }
                            else { selectedLayouts.insert(opt) }
                        } label: {
                            Label(opt, systemImage: selectedLayouts.contains(opt) ? "checkmark.square.fill" : "square")
                        }
                    }
                    Divider()
                    Button("全部户型") { selectedLayouts.removeAll() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.on.square")
                        Text(selectedLayouts.isEmpty ? "全部户型" : "户型(\(selectedLayouts.count))")
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.themePanel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.themeBorder))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 130)
                .help("按户型多选筛选")

                Spacer()

                Picker("", selection: $viewMode) {
                    Text("网格").tag("网格")
                    Text("列表").tag("列表")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            // 多选工具条（批量已租 / 批量删除 / 合集分享）
            if selecting {
                HStack(spacing: 10) {
                    Text("已选 \(selectedKeys.count) 间")
                        .font(.system(size: 14, weight: .semibold))
                    Button("全选") { selectedKeys = Set(filtered.map { $0.id }) }.macSecondaryButton()
                    Button("取消选择") { selectedKeys.removeAll() }.macSecondaryButton()
                    Spacer()
                    if !collectionURL.isEmpty {
                        Text("合集链接已生成：\(collectionURL)")
                            .font(.system(size: 13)).foregroundColor(.themeAccent).lineLimit(1)
                    }
                    Button("批量已租") { batchMarkRented() }.macPrimaryButton().disabled(batchBusy || selectedKeys.isEmpty)
                    Button("批量删除") { batchDelete() }.macSecondaryButton().disabled(batchBusy || selectedKeys.isEmpty)
                    Button("合集分享") { shareCollection() }.macSecondaryButton().disabled(batchBusy || selectedKeys.isEmpty)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.themePanel)
                Divider()
            }

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "house")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("没有符合条件的房源")
                        .font(.system(size: 16))
                        .foregroundColor(.themeText3)
                    Button("新增房源") { showNew = true }
                        .macSecondaryButton()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewMode == "网格" {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14)], spacing: 14) {
                        ForEach(filtered) { house in
                            HouseCard(house: house, isSelected: selectedKeys.contains(house.id), showCheck: selecting,
                                     onEdit: { editingHouse = house },
                                     onShare: { sharingHouse = house },
                                     onDelete: { confirmDelete(house) }) {
                                if selecting {
                                    if selectedKeys.contains(house.id) { selectedKeys.remove(house.id) }
                                    else { selectedKeys.insert(house.id) }
                                } else {
                                    selectedHouse = house
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                List {
                    ForEach(filtered) { house in
                        HouseRow(house: house, isSelected: selectedKeys.contains(house.id), showCheck: selecting,
                                onEdit: { editingHouse = house },
                                onShare: { sharingHouse = house },
                                onDelete: { confirmDelete(house) })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selecting {
                                    if selectedKeys.contains(house.id) { selectedKeys.remove(house.id) }
                                    else { selectedKeys.insert(house.id) }
                                } else {
                                    selectedHouse = house
                                }
                            }
                    }
                }
            }
        }
        .background(Color.themeBg)
        .sheet(isPresented: $showNew) {
            HouseEditView(manager: manager, house: nil) {
                showNew = false
            }
        }
        .sheet(isPresented: $showTrash) {
            TrashView(manager: manager) { showTrash = false }
        }
        .sheet(item: $selectedHouse) { house in
            HouseDetailView(manager: manager, house: house) {
                selectedHouse = nil
            }
        }
        .sheet(item: $editingHouse) { house in
            HouseEditView(manager: manager, house: house) {
                editingHouse = nil
            }
        }
        .sheet(item: $sharingHouse) { house in
            ShareMenuView(manager: manager, house: house) {
                sharingHouse = nil
            }
        }
        .confirmationDialog("确定删除 \(pendingDelete?.displayRoomNo ?? "") 吗？删除后可到回收站还原。",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let h = pendingDelete {
                    manager.softDeleteHouse(h)
                    MacToastCenter.show("已删除，可在回收站还原")
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .sheet(isPresented: $showBatchImport) {
            HouseBatchImportView(manager: manager) {
                showBatchImport = false
            }
        }
        .alert("刷新同步", isPresented: Binding(get: { syncAlert != nil }, set: { if !$0 { syncAlert = nil } })) {
            Button("取消", role: .cancel) { syncAlert = nil }
            Button("确认同步") {
                let msg = syncAlert
                syncAlert = nil
                syncing = true
                Task {
                    syncMinimized = false
                    SyncTaskCenter.shared.begin(title: "云端同步", roomKeys: filtered.map { $0.mediaRoomKey }, total: filtered.count)
                    let result = await manager.syncFromCloud { p, label in
                        Task { @MainActor in
                            syncProgress = p
                            syncStatus = label
                            SyncTaskCenter.shared.advance(done: Int(p * Double(max(filtered.count, 1))), current: label)
                        }
                    }
                    await MainActor.run { syncing = false; syncProgress = 0; syncStatus = ""
                        SyncTaskCenter.shared.finish(success: { if case .success = result { return true } else { return false } }())
                    }
                    if case .failure(let e) = result {
                        MacToastCenter.show("同步失败：\(e)")
                    } else if case .success(let a, let u, let r, _) = result {
                        MacToastCenter.show("同步完成：新增 \(a) · 更新 \(u) · 删除 \(r)")
                    }
                    _ = msg
                }
            }
        } message: {
            Text(syncAlert ?? "")
        }
    }

    // MARK: 本地刷新——媒体补全检测（对齐 iOS v1.63：不再触发云端同步）
    /// 磁盘有而记录没有 → 自动补建媒体记录；记录有而磁盘没有 → 提示待云端回补；
    /// 无对应房源的目录 → 提示可扫描补录。有变化列明细，无变化提示「已刷新，无变化」。
    private func localRefreshWithMediaCheck() {
        localRefreshing = true
        let ctx = manager.houseContext
        Task {
            let all = (try? ctx.fetch(FetchDescriptor<House>())) ?? []
            let active = all.filter { !($0.isDeleted ?? false) }
            var addedLines: [String] = []
            var missingLines: [String] = []
            var addedCount = 0
            var addedFiles = 0
            var inserted: [MediaItem] = []
            for house in active {
                let dir = MediaStore.houseDirectory(roomKey: house.mediaRoomKey)
                let disk = Set(MediaStore.mediaFileNames(in: dir))
                let recorded = Set(house.mediaItems.map { $0.fileName })
                let toAdd = disk.subtracting(recorded)
                let missing = recorded.subtracting(disk)
                if !toAdd.isEmpty {
                    for f in toAdd.sorted() {
                        let lower = f.lowercased()
                        let media = MediaItem(fileName: f, kind: (lower.hasSuffix(".mp4") || lower.hasSuffix(".mov")) ? "video" : "image")
                        media.house = house
                        ctx.insert(media)
                        inserted.append(media)
                        addedFiles += 1
                    }
                    addedCount += 1
                    addedLines.append("\(house.displayRoomNo)：补全 \(toAdd.count) 个媒体")
                }
                if !missing.isEmpty {
                    missingLines.append("\(house.displayRoomNo)：本地缺 \(missing.count) 个文件（云端回补）")
                }
            }
            var lines: [String] = []
            if !inserted.isEmpty { try? ctx.save() }
            // 未收录目录：media 下有目录但无对应房源
            let keys = MediaStore.scanMediaDirectoryKeys()
            let orphanKeys = keys.filter { key in
                !active.contains { $0.mediaRoomKey == key }
            }
            if addedCount > 0 {
                lines.append("媒体补全 \(addedCount) 间（\(addedFiles) 个文件）：")
                lines.append(contentsOf: addedLines)
            }
            if !missingLines.isEmpty {
                lines.append("待云端回补：" + missingLines.joined(separator: "；"))
            }
            if !orphanKeys.isEmpty {
                lines.append("未收录目录 \(orphanKeys.count) 个：\(orphanKeys.prefix(5).joined(separator: "、"))（可去批量录入-扫描补录导入）")
            }
            await MainActor.run {
                localRefreshing = false
                if lines.isEmpty {
                    MacToastCenter.show("已刷新，无变化")
                } else {
                    MacToastCenter.show(lines.joined(separator: "\n"))
                }
                NotificationCenter.default.post(name: .macHouseChanged, object: nil)
            }
        }
    }

    // MARK: 列表刷新同步（P1-1 第 3 点：dryRun 差异预览 → 确认后应用）

    private func refreshSync() {
        guard CosConfig.load() != nil else {
            MacToastCenter.show("未配置云端，先到设置页配置")
            return
        }
        syncing = true
        Task {
            let dry = await CloudHouseSync.pullAndMerge(houseContext: manager.houseContext, apply: false) { p, label in
                Task { @MainActor in
                    syncProgress = p
                    syncStatus = label
                }
            }
            await MainActor.run { syncing = false; syncProgress = 0; syncStatus = "" }
            switch dry {
            case .success(let added, let updated, let removed, let detail):
                if added == 0 && updated == 0 && removed == 0 {
                    MacToastCenter.show("云端与本机一致，无需同步")
                } else {
                    syncAlert = "检测到云端变化：\n\(detail)\n\n确认后将从云端拉取并覆盖本机对应房源。"
                }
            case .failure(let msg):
                MacToastCenter.show("检查云端失败：\(msg)")
            }
        }
    }

    // MARK: 多选批量操作（对齐 iOS v1.12/v1.16/v1.59）

    private func batchMarkRented() {
        batchBusy = true
        for house in filtered where selectedKeys.contains(house.id) {
            if house.isRented { continue }
            house.status = "已租"
            house.lastUpdatedAt = Date()
        }
        try? manager.houseContext.save()
        NotificationCenter.default.post(name: .macHouseChanged, object: nil)
        CloudOps.log(category: "房源", action: "批量已租", result: "成功", detail: "已租 \(selectedKeys.count) 套")
        Task {
            if CosConfig.load() != nil { _ = await manager.pushToCloud() }
            selectedKeys.removeAll()
            selecting = false
            batchBusy = false
            MacToastCenter.show("已批量标记已租并推送云端")
        }
    }

    private func batchDelete() {
        batchBusy = true
        var count = 0
        for house in filtered where selectedKeys.contains(house.id) {
            manager.softDeleteHouse(house)
            count += 1
        }
        Task {
            if CosConfig.load() != nil { _ = await manager.pushToCloud() }
            selectedKeys.removeAll()
            selecting = false
            batchBusy = false
            MacToastCenter.show("已删除 \(count) 间（可到回收站恢复）")
        }
    }

    private func shareCollection() {
        guard let config = CosConfig.load() else {
            MacToastCenter.show("未配置云端，无法生成合集分享")
            return
        }
        batchBusy = true
        collectionURL = ""
        let houses = filtered.filter { selectedKeys.contains($0.id) }
        let rooms = houses.map { house -> ShareCollectionItem in
            ShareCollectionItem(
                roomKey: house.mediaRoomKey,
                displayRoomNo: house.displayRoomNo,
                towerLabel: house.towerLabel,
                layout: house.layout,
                statusLabel: house.status,
                priceText: "\(house.price)元",
                landlord: house.landlord,
                password: house.password,
                remark: house.remark,
                mediaFiles: house.mediaItems.map { ShareMediaFile(name: $0.fileName, kind: $0.kind) }
            )
        }
        Task {
            do {
                let url = try await CosUploader.shareCollection(rooms: rooms, config: config)
                await MainActor.run {
                    collectionURL = url
                    batchBusy = false
                    MacToastCenter.show("合集分享页已生成")
                }
            } catch {
                await MainActor.run {
                    batchBusy = false
                    MacToastCenter.show("合集分享失败：\(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - 网格卡片（正方形，封面为视频预览帧）

struct HouseCard: View {
    let house: House
    var isSelected: Bool = false
    var showCheck: Bool = false
    var onEdit: () -> Void = {}
    var onShare: () -> Void = {}
    var onDelete: () -> Void = {}
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    // 严格正方形缩略图容器（自适应列宽，不再被拉成长方形）
                    GeometryReader { geo in
                        MediaThumbView(house: house, size: max(geo.size.width, geo.size.height))
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .aspectRatio(1, contentMode: .fit)
                    HStack {
                        StatusBadge(status: house.status)
                        Spacer()
                        Text(house.photoSummary)
                            .font(.system(size: 11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.55))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    .padding(6)
                    if showCheck {
                        ZStack(alignment: .topTrailing) {
                            Color.clear
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(isSelected ? .themeAccent : .white.opacity(0.85))
                                .background(Circle().fill(Color.black.opacity(0.35)))
                                .padding(6)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    // 第一行：房号（左） | 户型+房东（中） | 价格（右）
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(house.displayRoomNo)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.themeText)
                            .lineLimit(1)
                        Spacer()
                        HStack(spacing: 5) {
                            Text(house.layout)
                                .font(.system(size: 12))
                                .foregroundColor(.themeText3)
                                .lineLimit(1)
                            Text(house.landlord)
                                .font(.system(size: 12))
                                .foregroundColor(.themeText2)
                                .lineLimit(1)
                        }
                        .layoutPriority(1)
                        Spacer()
                        Text("¥\(house.price)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.themeDanger)
                    }
                    // 第二行：备注（左，无备注显示-） | 双端标识（右）
                    HStack {
                        Text(house.remark.isEmpty ? "-" : house.remark)
                            .font(.system(size: 12))
                            .foregroundColor(.themeText3)
                            .lineLimit(1)
                        Spacer()
                        CloudStatusBadge(raw: house.cloudStatusRaw)
                    }
                }
                .padding(10)
            }
            .background(Color.themeCard)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑") { onEdit() }
            Button("分享") { onShare() }
            Button("删除", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - 列表行

struct HouseRow: View {
    let house: House
    var isSelected: Bool = false
    var showCheck: Bool = false
    var onEdit: () -> Void = {}
    var onShare: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            if showCheck {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .themeAccent : .themeText3)
            }
            MediaThumbView(house: house, size: 44)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(house.displayRoomNo)
                        .font(.system(size: 15, weight: .semibold))
                    StatusBadge(status: house.status)
                    CloudStatusBadge(raw: house.cloudStatusRaw)
                }
                Text("\(house.layout) · \(house.landlord) · ¥\(house.price)/月")
                    .font(.system(size: 14))
                    .foregroundColor(.themeText2)
            }
            Spacer()
            Text(house.photoSummary)
                .font(.system(size: 13))
                .foregroundColor(.themeText3)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("编辑") { onEdit() }
            Button("分享") { onShare() }
            Button("删除", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - 视频首帧缩略图缓存（对齐 iOS：视频卡显示首帧 + 播放角标）

enum VideoThumbCache {
    private static let memCache = NSCache<NSString, NSImage>()

    /// 取视频首帧（内存缓存 → 磁盘 .thumb.jpg → AVAssetImageGenerator 生成并落盘）
    static func load(roomKey: String, fileName: String) -> NSImage? {
        let cacheKey = "\(roomKey)/\(fileName)" as NSString
        if let hit = memCache.object(forKey: cacheKey) { return hit }

        let videoURL = MediaStore.fileURL(fileName: fileName, roomKey: roomKey)
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return nil }

        let thumbURL = videoURL.deletingPathExtension().appendingPathExtension("thumb.jpg")
        if let disk = NSImage(contentsOf: thumbURL) {
            memCache.setObject(disk, forKey: cacheKey)
            return disk
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        guard let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) else {
            return nil
        }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        // 落盘缓存（NSBitmapImageRep → JPEG）
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) {
            try? jpg.write(to: thumbURL)
        }
        memCache.setObject(img, forKey: cacheKey)
        return img
    }
}

// MARK: - 双端状态徽标（cloudStatusRaw：local 本地 / cloud 云端 / both 双端）

struct CloudStatusBadge: View {
    let raw: String?
    var body: some View {
        // v1.2.11：未配置云端时不存在云端数据，一律显示「本地」，避免误标云端
        let effective: String? = CosConfig.load() == nil ? "local" : raw
        switch effective {
        case "both":
            Text("双端").font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundColor(ThemeManager.isDark ? Color(red: 0.55, green: 0.88, blue: 0.70) : Color(hex: "00695C"))
                .background(ThemeManager.isDark ? Color(red: 0.15, green: 0.30, blue: 0.23) : Color(hex: "E0F2F1"))
                .clipShape(Capsule())
        case "cloud":
            Text("云端").font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundColor(ThemeManager.isDark ? Color(red: 0.58, green: 0.78, blue: 1.0) : Color(hex: "1565C0"))
                .background(ThemeManager.isDark ? Color(red: 0.16, green: 0.24, blue: 0.36) : Color(hex: "E3F2FD"))
                .clipShape(Capsule())
        case "local":
            Text("本地").font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundColor(ThemeManager.isDark ? Color(red: 0.88, green: 0.76, blue: 0.62) : Color(hex: "6D4C41"))
                .background(ThemeManager.isDark ? Color(red: 0.30, green: 0.26, blue: 0.22) : Color(hex: "EFEBE9"))
                .clipShape(Capsule())
        default:
            EmptyView()
        }
    }
}
