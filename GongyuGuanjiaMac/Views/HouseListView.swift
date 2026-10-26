import SwiftUI
import SwiftData
import AppKit

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

    var body: some View {
        Group {
            if let item {
                if item.kind == "image", let nsImage = loadImage(item.fileName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // 视频：显示首帧或播放图标
                    ZStack {
                        if let nsImage = loadImage(item.fileName) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.25)
                            Image(systemName: "video.fill")
                                .font(.system(size: size * 0.25))
                                .foregroundColor(.white)
                        }
                    }
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
    @State private var statusFilter = "全部"
    @State private var viewMode = "网格"
    @State private var selectedHouse: House?
    @State private var showNew = false
    @State private var showBatchImport = false
    @State private var selecting = false          // 多选模式
    @State private var selectedKeys: Set<UUID> = []
    @State private var batchBusy = false
    @State private var collectionURL = ""
    @State private var syncing = false
    @State private var syncAlert: String?

    private var houses: [House] { manager.houses }

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

    var body: some View {
        VStack(spacing: 0) {
            // 顶部
            HStack(spacing: 10) {
                Text("房源管理")
                    .font(.system(size: 20, weight: .bold))
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
                    refreshSync()
                } label: {
                    Label(syncing ? "同步中…" : "刷新同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .macSecondaryButton()
                .disabled(syncing)
                Button {
                    showNew = true
                } label: {
                    Label("新增房源", systemImage: "plus")
                }
                .macPrimaryButton()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // 统计行
            HStack(spacing: 12) {
                Text("共 \(stats.total) 套")
                    .font(.system(size: 14))
                    .foregroundColor(.themeText2)
                Text("1座 \(stats.tower1) 套")
                    .font(.system(size: 14))
                    .foregroundColor(.themeText2)
                Text("2座 \(stats.tower2) 套")
                    .font(.system(size: 14))
                    .foregroundColor(.themeText2)
                Text("待租 \(stats.available) · 已租 \(stats.rented)")
                    .font(.system(size: 14))
                    .foregroundColor(.themeText2)
                Text("有实拍图 \(stats.withPhoto) · 无实拍图 \(stats.withoutPhoto)")
                    .font(.system(size: 14))
                    .foregroundColor(.themeText2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

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
                            HouseCard(house: house, isSelected: selectedKeys.contains(house.id), showCheck: selecting) {
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
                        HouseRow(house: house, isSelected: selectedKeys.contains(house.id), showCheck: selecting)
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
        .sheet(item: $selectedHouse) { house in
            HouseDetailView(manager: manager, house: house) {
                selectedHouse = nil
            }
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
                    let result = await manager.syncFromCloud()
                    await MainActor.run { syncing = false }
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

    // MARK: 列表刷新同步（P1-1 第 3 点：dryRun 差异预览 → 确认后应用）

    private func refreshSync() {
        guard CosConfig.load() != nil else {
            MacToastCenter.show("未配置云端，先到设置页配置")
            return
        }
        syncing = true
        Task {
            let dry = await CloudHouseSync.pullAndMerge(houseContext: manager.houseContext, apply: false)
            await MainActor.run { syncing = false }
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
                priceText: "\(Int(house.price))元",
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    MediaThumbView(house: house, size: 240)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
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
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(house.displayRoomNo)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.themeText)
                        Text(house.towerLabel)
                            .font(.system(size: 13))
                            .foregroundColor(.themeText3)
                        Spacer()
                        Text("¥\(Int(house.price))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.themeDanger)
                    }
                    HStack {
                        Text(house.layout)
                            .font(.system(size: 14))
                            .foregroundColor(.themeText2)
                        Text("房东 \(house.landlord)")
                            .font(.system(size: 13))
                            .foregroundColor(.themeText3)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .padding(10)
            }
            .background(Color.white)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 列表行

struct HouseRow: View {
    let house: House
    var isSelected: Bool = false
    var showCheck: Bool = false

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
                }
                Text("\(house.layout) · 房东 \(house.landlord) · ¥\(Int(house.price))/月")
                    .font(.system(size: 14))
                    .foregroundColor(.themeText2)
            }
            Spacer()
            Text(house.photoSummary)
                .font(.system(size: 13))
                .foregroundColor(.themeText3)
        }
        .padding(.vertical, 4)
    }
}
