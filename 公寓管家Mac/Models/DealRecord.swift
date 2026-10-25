import Foundation
import SwiftData

// MARK: - 成交记录（与 iOS 版 DealRecord 对齐）

@Model
final class DealRecord {
    @Attribute(.unique) var id: UUID
    var roomNo: String
    var dealDate: Date
    var dealType: String        // 成交类型
    var price: Double
    var commission: Double
    var fee: Double             // 杂费/其他费用
    var paidBy: String          // 付款方
    var remark: String
    var createdAt: Date
    var updatedAt: Date

    init(roomNo: String, dealDate: Date, dealType: String, price: Double,
         commission: Double = 0, fee: Double = 0, paidBy: String = "", remark: String = "") {
        self.id = UUID()
        self.roomNo = roomNo
        self.dealDate = dealDate
        self.dealType = dealType
        self.price = price
        self.commission = commission
        self.fee = fee
        self.paidBy = paidBy
        self.remark = remark
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
