import Foundation

struct AssetSymbol: Equatable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalized.isEmpty else {
            throw DomainValidationError.emptyAssetSymbol
        }

        self.rawValue = normalized
    }

    private init(normalized: String) {
        rawValue = normalized
    }

    static let btc = AssetSymbol(normalized: "BTC")
    static let eth = AssetSymbol(normalized: "ETH")
    static let sol = AssetSymbol(normalized: "SOL")
    static let usdt = AssetSymbol(normalized: "USDT")
    static let usdc = AssetSymbol(normalized: "USDC")
}

extension AssetSymbol: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
