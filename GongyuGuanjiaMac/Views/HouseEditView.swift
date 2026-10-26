import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 房源编辑（新增/编辑共用，带明确关闭按钮）

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

    private var isEdit: Bool { house != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isEdit ? "编辑房源" : "新增房源")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Group {
                HStack(spacing: 10) {
                    TextField("房号（如 2334）", text: $roomNo)
                    Picker("座号", selection: $tower) {
                        Text("1座").tag(1)
                        Text("2座").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
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

            // 新增时的媒体选择
            if !isEdit {
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
                            .font(.system(size: 13))
                            .foregroundColor(.themeText2)
                    }
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13))
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
        .frame(width: 500)
        .onAppear {
            if let house = house {
                roomNo = house.roomNo
                tower = house.tower
                landlord = house.landlord
                layout = house.layout
                price = "\(Int(house.price))"
                password = house.password
                remark = house.remark
                status = house.status
            }
        }
    }

    private func save() {
        let roomNoTrim = roomNo.trimmingCharacters(in: .whitespaces)
        guard !roomNoTrim.isEmpty else { errorMessage = "请填写房号"; return }
        guard !landlord.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "请填写房东"; return }
        guard !layout.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "请填写户型"; return }
        guard let priceValue = Double(price), priceValue > 0 else { errorMessage = "请填写正确的租金"; return }

        // 房号命名规则：2 座自动处理（房号本体不带 2- 前缀）
        var finalRoomNo = roomNoTrim
        var finalTower = tower
        if finalRoomNo.hasPrefix("2-") {
            finalTower = 2
            finalRoomNo = String(finalRoomNo.dropFirst(2))
        }

        if let house = house {
            manager.updateHouse(house, roomNo: finalRoomNo, tower: finalTower,
                                landlord: landlord.trimmingCharacters(in: .whitespaces),
                                layout: layout.trimmingCharacters(in: .whitespaces),
                                price: priceValue, password: password, remark: remark, status: status)
            MacToastCenter.show("已保存修改，分享页已自动更新")
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
