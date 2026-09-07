import Foundation
import SwiftData

@Model
final class PortfolioAnalysisEntity {
    @Attribute(.unique) var id: UUID
    var generatedAt: Date
    var snapshotID: UUID
    var payload: Data

    init(id: UUID, generatedAt: Date, snapshotID: UUID, payload: Data) {
        self.id = id
        self.generatedAt = generatedAt
        self.snapshotID = snapshotID
        self.payload = payload
    }
}
