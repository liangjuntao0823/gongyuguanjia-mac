import Foundation
import SwiftData

// MARK: - 物业（包租板块）

@Model
final class Property {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var monthlyRent: Double
    var monthlyExpense: Double
    var remark: String
    var createdAt: Date
    var updatedAt: Date

    init(name: String, address: String = "", monthlyRent: Double = 0,
         monthlyExpense: Double = 0, remark: String = "") {
        self.id = UUID()
        self.name = name
        self.address = address
        self.monthlyRent = monthlyRent
        self.monthlyExpense = monthlyExpense
        self.remark = remark
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
