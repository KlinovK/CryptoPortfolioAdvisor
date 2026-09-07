import Foundation

enum TradingStyle: String, Equatable, Codable, Sendable {
    case active
}

enum RiskTolerance: String, Equatable, Codable, Sendable {
    case conservative
    case moderate
    case aggressive
}

struct TradingConstraints: Equatable, Codable, Sendable {
    let tradingStyle: TradingStyle
    let riskTolerance: RiskTolerance
    let leverageAllowed: Bool
    let additionalMonthlyIncomeUSD: Decimal
    let minimumStableReserveUSD: Decimal

    init(
        tradingStyle: TradingStyle,
        riskTolerance: RiskTolerance,
        leverageAllowed: Bool,
        additionalMonthlyIncomeUSD: Decimal,
        minimumStableReserveUSD: Decimal
    ) throws {
        guard additionalMonthlyIncomeUSD >= 0 else {
            throw DomainValidationError.negativeAdditionalMonthlyIncomeUSD
        }

        guard minimumStableReserveUSD >= 0 else {
            throw DomainValidationError.negativeMinimumStableReserveUSD
        }

        self.tradingStyle = tradingStyle
        self.riskTolerance = riskTolerance
        self.leverageAllowed = leverageAllowed
        self.additionalMonthlyIncomeUSD = additionalMonthlyIncomeUSD
        self.minimumStableReserveUSD = minimumStableReserveUSD
    }

    private enum CodingKeys: CodingKey {
        case tradingStyle
        case riskTolerance
        case leverageAllowed
        case additionalMonthlyIncomeUSD
        case minimumStableReserveUSD
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            tradingStyle: container.decode(TradingStyle.self, forKey: .tradingStyle),
            riskTolerance: container.decode(RiskTolerance.self, forKey: .riskTolerance),
            leverageAllowed: container.decode(Bool.self, forKey: .leverageAllowed),
            additionalMonthlyIncomeUSD: container.decode(
                Decimal.self,
                forKey: .additionalMonthlyIncomeUSD
            ),
            minimumStableReserveUSD: container.decode(
                Decimal.self,
                forKey: .minimumStableReserveUSD
            )
        )
    }
}
