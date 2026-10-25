import Foundation
import SwiftData

// MARK: - 房源（House）与媒体（MediaItem）——与 iOS 版字段完全对齐

@Model
final class House {
    @Attribute(.unique) var id: UUID
    var roomNo: String          // 房号本体（2 座不带 2- 前缀，展示时自动加）
    var tower: Int              // 座号 1/2
    var landlord: String
    var layout: String          // 户型
    var price: Double
    var password: String
    var remark: String
    var statusRaw: String       // "待租" / "已租"
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool?
    var deletedAt: Date?
    var cloudStatusRaw: String? // "local" / "cloud" / "both"
    var updatedBy: String?      // 云端同步时记录最后修改者

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.house)
    var mediaItems: [MediaItem]

    init(roomNo: String, tower: Int, landlord: String, layout: String, price: Double,
         password: String = "", remark: String = "", status: String = "待租") {
        self.id = UUID()
        self.roomNo = roomNo
        self.tower = tower
        self.landlord = landlord
        self.layout = layout
        self.price = price
        self.password = password
        self.remark = remark
        self.statusRaw = status
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isDeleted = false
        self.deletedAt = nil
        self.cloudStatusRaw = nil
        self.updatedBy = nil
        self.mediaItems = []
    }

    // MARK: 状态
    var status: String {
        get { statusRaw }
        set { statusRaw = newValue; updatedAt = Date() }
    }

    var isRented: Bool { statusRaw == "已租" }
    var isAvailable: Bool { statusRaw == "待租" }

    // MARK: 云端三态
    enum CloudStatus: String {
        case local = "local"
        case cloud = "cloud"
        case both = "both"
    }
    var cloudStatus: CloudStatus {
        get { CloudStatus(rawValue: cloudStatusRaw ?? "") ?? .local }
        set { cloudStatusRaw = newValue.rawValue }
    }
    var isInCloud: Bool { cloudStatus == .cloud || cloudStatus == .both }

    // MARK: 展示
    var towerLabel: String { "\(tower)座" }

    /// 房号展示：2 座自动加「2-」前缀，1 座不带（若录入带 1- 前缀则原样保留，兼容历史）
    var displayRoomNo: String {
        if tower == 2 && !roomNo.hasPrefix("2-") { return "2-\(roomNo)" }
        return roomNo
    }

    /// 媒体目录名（云端 key 也用这个）：2 座带前缀，去非法字符
    var mediaRoomKey: String {
        let raw = tower == 2 ? "2-\(roomNo)" : roomNo
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return raw.components(separatedBy: illegal).joined(separator: "-")
    }

    /// 排序数字串：从末尾提取第一段连续数字（忽略座号前缀与「上/下/层」后缀）
    var sortDigits: String {
        var collected = ""
        for ch in roomNo.reversed() {
            if ch.isNumber {
                collected.append(ch)
            } else if !collected.isEmpty {
                break
            }
        }
        return String(collected.reversed())
    }

    var hasMedia: Bool { !mediaItems.isEmpty }
    var imageCount: Int { mediaItems.filter { $0.kind == "image" }.count }
    var videoCount: Int { mediaItems.filter { $0.kind == "video" }.count }
    var hasRealPhoto: Bool { imageCount > 0 }

    /// 列表显示「有实拍图 N 张」/「无实拍图」（v1.54 口径）
    var photoSummary: String {
        if imageCount == 0 { return "无实拍图" }
        return "有实拍图 \(imageCount) 张"
    }
}

// MARK: - 房源媒体

@Model
final class MediaItem {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var kind: String            // "image" / "video"
    var house: House?

    init(fileName: String, kind: String) {
        self.id = UUID()
        self.fileName = fileName
        self.kind = kind
    }
}

// MARK: - 房源导出 DTO（备份/同步用，与 iOS 版 HouseBundleDTO 对齐）

struct HouseExportDTO: Codable {
    var id: UUID
    var roomNo: String
    var tower: Int
    var landlord: String
    var layout: String
    var price: Double
    var password: String
    var remark: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool?
    var deletedAt: Date?
    var mediaItems: [MediaExportDTO]
}

struct MediaExportDTO: Codable {
    var fileName: String
    var kind: String
}

struct HouseBundleDTO: Codable {
    var schemaVersion: Int
    var houses: [HouseExportDTO]
}
