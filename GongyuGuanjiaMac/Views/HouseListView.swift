import SwiftUI
import SwiftData
import AppKit

// MARK: - 共享房源组件（缩略图 / 状态徽标）

/// 房源媒体缩略图：图片直接显示；视频显示首帧或播放图标
struct MediaThumbView: View {
    let house: House
    let size: CGFloat

    var body: some View {
        Group {
            if let first = firstDisplayMedia {
                if first.kind == "image", let nsImage = loadImage(first.fileName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // 视频：显示播放图标
                    ZStack {
                        if let nsImage = loadImage(first.fileName) {
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

    /// 优先视频（与 iOS 版「封面直接房视频预览图」一致）
    private var firstDisplayMedia: MediaItem? {
        house.mediaItems.first { $0.kind == "video" } ?? house.mediaItems.first { $0.kind == "image" }
    }

    private func loadImage(_ fileName: String) -> NSImage? {
        let url = MediaStore.fileURL(fileName: fileName, roomKey: house.mediaRoomKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status)
            .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                Button {
                    showBatchImport = true
                } label: {
                    Label("批量导入", systemImage: "square.and.arrow.down")
                }
                .macSecondaryButton()
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
                    .font(.system(size: 12))
                    .foregroundColor(.themeText2)
                Text("1座 \(stats.tower1) 套")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText2)
                Text("2座 \(stats.tower2) 套")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText2)
                Text("待租 \(stats.available) · 已租 \(stats.rented)")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText2)
                Text("有实拍图 \(stats.withPhoto) · 无实拍图 \(stats.withoutPhoto)")
                    .font(.system(size: 12))
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

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "house")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("没有符合条件的房源")
                        .font(.system(size: 14))
                        .foregroundColor(.themeText3)
                    Button("新增房源") { showNew = true }
                        .macSecondaryButton()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewMode == "网格" {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14)], spacing: 14) {
                        ForEach(filtered) { house in
                            HouseCard(house: house) {
                                selectedHouse = house
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                List {
                    ForEach(filtered) { house in
                        HouseRow(house: house)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedHouse = house }
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
    }
}

// MARK: - 网格卡片（正方形，封面为视频预览帧）

struct HouseCard: View {
    let house: House
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
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.55))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    .padding(6)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(house.displayRoomNo)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.themeText)
                        Text(house.towerLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.themeText3)
                        Spacer()
                        Text("¥\(Int(house.price))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.themeDanger)
                    }
                    HStack {
                        Text(house.layout)
                            .font(.system(size: 12))
                            .foregroundColor(.themeText2)
                        Text("房东 \(house.landlord)")
                            .font(.system(size: 11))
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

    var body: some View {
        HStack(spacing: 12) {
            MediaThumbView(house: house, size: 44)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(house.displayRoomNo)
                        .font(.system(size: 14, weight: .semibold))
                    StatusBadge(status: house.status)
                }
                Text("\(house.layout) · 房东 \(house.landlord) · ¥\(Int(house.price))/月")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText2)
            }
            Spacer()
            Text(house.photoSummary)
                .font(.system(size: 11))
                .foregroundColor(.themeText3)
        }
        .padding(.vertical, 4)
    }
}
