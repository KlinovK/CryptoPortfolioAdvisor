import Foundation

struct AssetPosition: Equatable, Codable, Sendable {
    let symbol: AssetSymbol
    let amount: Decimal

    init(symbol: AssetSymbol, amount: Decimal) throws {
        guard amount >= 0 else {
            throw DomainValidationError.negativeAssetAmount
        }

        self.symbol = symbol
        self.amount = amount
    }

    private enum CodingKeys: CodingKey {
        case symbol
        case amount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            symbol: container.decode(AssetSymbol.self, forKey: .symbol),
            amount: container.decode(Decimal.self, forKey: .amount)
        )
    }
}
