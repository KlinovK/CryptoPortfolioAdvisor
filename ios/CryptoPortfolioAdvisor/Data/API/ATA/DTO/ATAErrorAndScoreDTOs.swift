import Foundation

struct ATAErrorEnvelopeDTO: Decodable, Equatable, Sendable {
    let error: Detail

    struct Detail: Decodable, Equatable, Sendable {
        let code: String
        let message: String
        let reloadRequired: Bool?

        private enum CodingKeys: String, CodingKey {
            case code, message
            case reloadRequired = "reload_required"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            message = try c.decode(String.self, forKey: .message)
            if c.contains(.reloadRequired) {
                guard try c.decode(Bool.self, forKey: .reloadRequired) else {
                    throw ATAWireError.invalidValue
                }
                reloadRequired = true
            } else {
                reloadRequired = nil
            }
        }
    }
}

// The backend intentionally uses [name, points, maximum], not a JSON object.
struct ATAScoreComponentDTO: Decodable, Equatable, Sendable {
    let name: String
    let points: Int
    let maximum: Int

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        name = try c.decode(String.self)
        points = try c.decode(Int.self)
        maximum = try c.decode(Int.self)
        guard c.isAtEnd else { throw ATAWireError.invalidValue }
    }
}
