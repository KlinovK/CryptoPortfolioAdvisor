import Foundation
import SwiftData

@Model
final class PortfolioSnapshotEntity {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var payload: Data

    init(id: UUID, createdAt: Date, payload: Data) {
        self.id = id
        self.createdAt = createdAt
        self.payload = payload
    }
}
