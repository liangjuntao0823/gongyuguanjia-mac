import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 房源编辑（新增/编辑共用，带明确关闭按钮）
// v1.2 对齐 iOS v1.69：房号前缀强制（1-/2-）、实时查重、编辑页媒体管理（删旧传新一次保存）

struct HouseEditView: View {
    @ObservedObject var manager: DataManager
    let house: House?
    let onClose: () -> Void

    @State private var roomNo = ""
    @State private var tower = 1
    @State private var landlord = ""
    @State private var layout = ""
    @State private var price = ""
    @State private var password = ""
    @State private var remark = ""
    @State private var status = "待租"
    @State private var addedFiles: [(URL, String)] = []
    @State private var errorMessage = ""
    @State private var duplicateMessage = ""
    @State private var mediaToRemove: Set<String> = []

    private var isEdit: Bool { house != nil }

    /// 归一化房号（去前缀去空格，查重用）
    private func normalizedRoomNo(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("1-") || v.hasPrefix("2-") { v = String(v.dropFirst(2)) }
        return v
    }

    private func checkDuplicate() {
        let target = normalizedRoomNo(roomNo)
        guard !target.isEmpty else { duplicateMessage = ""; return }
        let sameTower = manager.houses.contains {
            $0.isDeleted != true && $0.tower == tower && normalizedRoomNo($0.roomNo) == target
        }
        let otherTower = manager.houses.contains {
            $0.isDeleted != true && $0.tower != tower && normalizedRoomNo($0.roomNo) == target
        }
        if sameTower {
            duplicateMessage = "该房号已收录（\(tower)座），请勿重复添加"
        } else if otherTower {
            duplicateMessage = "该房号在另一座已收录，请核对座号与房号"
        } else {
            duplicateMessage = ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isEdit ? "编辑房源" : "新增房源")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Group {
                HStack(spacing: 10) {
                    TextField("房号（如 1-2334上 或 2-1418下）", text: $roomNo)
                    Picker("座号", selection: $tower) {
                        Text("1座").tag(1)
                        Text("2座").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
                if !duplicateMessage.isEmpty {
                    Text(duplicateMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.themeDanger)
                }
                TextField("房东", text: $landlord)
                HStack(spacing: 10) {
                    TextField("户型（如 单间/一房一厅）", text: $layout)
                    TextField("租金（元/月）", text: $price)
                        .frame(width: 130)
                }
                HStack(spacing: 10) {
                    TextField("门锁密码（可空）", text: $password)
                    Picker("状态", selection: $status) {
                        Text("待租").tag("待租")
                        Text("已租").tag("已租")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                TextField("备注（可空）", text: $remark)
            }
            .textFieldStyle(.roundedBorder)

            // 编辑模式：媒体网格（删旧 + 传新，一次保存）对齐 iOS v1.65
            if isEdit, let house = house {
                VStack(alignment: .leading, spacing: 8) {
                    Text("实拍图/视频（\(house.mediaItems.count - mediaToRemove.count) 个）")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.themeText2)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(house.mediaItems) { item in
                            if !mediaToRemove.contains(item.fileName) {
                                VStack(spacing: 2) {
                                    ZStack(alignment: .topTrailing) {
                                        MediaThumbView(item: item, roomKey: house.mediaRoomKey, size: 60)
                                        Button {
                                            mediaToRemove.insert(item.fileName)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.black.opacity(0.7)))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(2)
                                    }
                                    Text(item.kind == "video" ? "视频" : "图片")
                                        .font(.system(size: 10, weight: .medium)).foregroundColor(.themeText3)
                                }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button {
                            MacBridge.openFiles(allowedTypes: [.image, .movie], allowsMultiple: true) { urls in
                                for url in urls {
                                    let ext = url.pathExtension.lowercased()
                                    let kind = ["mp4", "mov", "m4v"].contains(ext) ? "video" : "image"
                                    addedFiles.append((url, kind))
                                }
                            }
                        } label: {
                            Label("添加图片/视频", systemImage: "photo.on.rectangle.angled")
                        }
                        .macSecondaryButton()
                        if !addedFiles.isEmpty {
                            Text("新增 \(addedFiles.count) 个")
                                .font(.system(size: 14, weight: .medium)).foregroundColor(.themeText2)
                        }
                    }
                }
            } else if !isEdit {
                HStack(spacing: 10) {
                    Button {
                        MacBridge.openFiles(allowedTypes: [.image, .movie], allowsMultiple: true) { urls in
                            for url in urls {
                                let ext = url.pathExtension.lowercased()
                                let kind = ["mp4", "mov", "m4v"].contains(ext) ? "video" : "image"
                                addedFiles.append((url, kind))
                            }
                        }
                    } label: {
                        Label("选择实拍图/视频", systemImage: "photo.on.rectangle.angled")
                    }
                    .macSecondaryButton()
                    if !addedFiles.isEmpty {
                        Text("已选 \(addedFiles.count) 个")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.themeText2)
                    }
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.themeDanger)
            }

            HStack {
                Spacer()
                Button("取消") { onClose() }
                    .macSecondaryButton()
                Button(isEdit ? "保存修改" : "添加房源") { save() }
                    .macPrimaryButton()
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            if let house = house {
                roomNo = house.roomNo
                tower = house.tower
                landlord = house.landlord
                layout = house.layout
                price = "\(house.price)"
                password = house.password
                remark = house.remark
                status = house.status
            }
        }
        .onChange(of: roomNo) { _, _ in checkDuplicate() }
        .onChange(of: tower) { _, _ in checkDuplicate() }
    }

    private func save() {
        let roomNoTrim = roomNo.trimmingCharacters(in: .whitespaces)
        // 前缀强制（对齐 iOS v1.69）：必须以 1- 或 2- 开头
        guard roomNoTrim.hasPrefix("1-") || roomNoTrim.hasPrefix("2-") else {
            errorMessage = "房号必须以座号前缀开头：1- 或 2-（如 1-2334上、2-1418下）"
            return
        }
        guard !landlord.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "请填写房东"; return }
        guard !layout.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "请填写户型"; return }
        guard let priceValue = Int(price), priceValue > 0 else { errorMessage = "请填写正确的租金"; return }

        // 从前缀解析座号与本体（前缀为准）
        let finalTower = roomNoTrim.hasPrefix("2-") ? 2 : 1
        let finalRoomNo = String(roomNoTrim.dropFirst(2))

        if let house = house {
            // 编辑：媒体 diff（删旧 + 传新）一次保存
            for name in mediaToRemove {
                if let item = house.mediaItems.first(where: { $0.fileName == name }) {
                    manager.removeMedia(item, from: house)
                }
            }
            for (url, kind) in addedFiles {
                manager.addMedia(to: house, url: url, kind: kind)
            }
            manager.updateHouse(house, roomNo: finalRoomNo, tower: finalTower,
                                landlord: landlord.trimmingCharacters(in: .whitespaces),
                                layout: layout.trimmingCharacters(in: .whitespaces),
                                price: priceValue, password: password, remark: remark, status: status)
            MacToastCenter.show("已保存修改（媒体已同步更新），分享页已自动更新")
        } else {
            _ = manager.addHouse(roomNo: finalRoomNo, tower: finalTower,
                                 landlord: landlord.trimmingCharacters(in: .whitespaces),
                                 layout: layout.trimmingCharacters(in: .whitespaces),
                                 price: priceValue, password: password, remark: remark, status: status,
                                 mediaFiles: addedFiles)
            MacToastCenter.show("房源已添加，脱敏版分享页已自动生成")
        }
        onClose()
    }
}
