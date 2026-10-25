import SwiftUI
import SwiftData

// MARK: - 回收站（软删除房源查看/恢复/彻底删除）

struct TrashView: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    private var houses: [House] { manager.houses }

    private var trashed: [House] {
        houses.filter { $0.isDeleted == true }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("回收站")
                    .font(.system(size: 17, weight: .bold))
                Text("\(trashed.count) 套")
                    .font(.system(size: 12))
                    .foregroundColor(.themeText3)
                Spacer()
                Button("关闭") { onClose() }
                    .macPrimaryButton()
            }
            .padding(14)
            .background(Color(red: 0.965, green: 0.968, blue: 0.97))
            Divider()

            if trashed.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("回收站为空")
                        .font(.system(size: 14))
                        .foregroundColor(.themeText3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(trashed) { house in
                        HStack(spacing: 12) {
                            MediaThumbView(house: house, size: 42)
                                .cornerRadius(6)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(house.displayRoomNo)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(house.layout)
                                        .font(.system(size: 12))
                                        .foregroundColor(.themeText2)
                                }
                                Text("删除于 \(house.deletedAt.map { FormatKit.dateTimeStr($0) } ?? "-")")
                                    .font(.system(size: 11))
                                    .foregroundColor(.themeText3)
                            }
                            Spacer()
                            Button("恢复") {
                                manager.restoreHouse(house)
                                MacToastCenter.show("已恢复 \(house.displayRoomNo)")
                            }
                            .macSecondaryButton()
                            Button("彻底删除") {
                                manager.permanentDeleteHouse(house)
                                MacToastCenter.show("已彻底删除（云端媒体与分享页一并删除）")
                            }
                            .macSecondaryButton()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(width: 620, height: 520)
        .background(Color.themeBg)
    }
}
