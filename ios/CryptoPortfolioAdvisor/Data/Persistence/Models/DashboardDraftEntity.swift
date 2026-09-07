import Foundation
import SwiftData

@Model
final class DashboardDraftEntity {
    @Attribute(.unique) var key: String
    var payload: Data

    init(key: String = "current", payload: Data) {
        self.key = key
        self.payload = payload
    }
}
