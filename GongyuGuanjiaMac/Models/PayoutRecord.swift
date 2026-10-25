import Foundation
import SwiftData

// MARK: - 支出记录（收租/包租板块）

@Model
final class PayoutRecord {
    @Attribute(.unique) var id: UUID
    var amount: Double
    var category: String
    var date: Date
    var remark: String
    var createdAt: Date
    var updatedAt: Date

    init(amount: Double, category: String, date: Date, remark: String = "") {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.date = date
        self.remark = remark
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
