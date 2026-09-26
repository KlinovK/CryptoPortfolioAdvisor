import Foundation

extension ATAResponseMapper {

    static func domain(from dto: ATAPositionDTO) throws -> ATAPosition {
        return try ATAPosition(
            symbol: try symbol(dto.symbol),
            amount: try ATADecimalCodec.decode(dto.amount)
        )
    }

    static func domain(from dto: ATAAccountDTO) throws -> ATAAccount {
        guard !dto.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            Set(dto.positions.map(\.symbol)).count == dto.positions.count
        else {
            throw ATAWireError.invalidValue
        }
        return ATAAccount(
            id: try identity(dto.id),
            name: dto.name,
            type: try enumeration(dto.type, as: ATAAccountType.self),
            positions: try dto.positions.map { try domain(from: $0) }
        )
    }

    static func domain(from dto: ATAFinancialSettingsDTO) throws -> ATAFinancialSettings {
        return ATAFinancialSettings(
            monthlyExpensesUSD: try ATADecimalCodec.decode(dto.monthlyExpensesUSD),
            targetExpenseRunwayMonths: try ATADecimalCodec.decode(dto.targetExpenseRunwayMonths)
        )
    }

    static func domain(from dto: ATACorePositionDTO) throws -> ATACorePosition {
        return ATACorePosition(
            symbol: try symbol(dto.symbol),
            hardFloor: try ATADecimalCodec.decode(dto.hardFloor),
            preferredQuantity: try ATADecimalCodec.decode(dto.preferredQuantity),
            policyVersion: dto.policyVersion
        )
    }

    static func domain(from dto: ATALimitOrderDTO) throws -> ATALimitOrder {
        return ATALimitOrder(
            id: try identity(dto.id),
            accountID: try identity(dto.accountID),
            asset: try symbol(dto.asset),
            side: try enumeration(dto.side, as: ATAOrderSide.self),
            targetPrice: try ATADecimalCodec.decode(dto.targetPrice),
            quantityAsset: try ATADecimalCodec.decode(dto.quantityAsset),
            status: try enumeration(dto.status, as: ATAOrderStatus.self),
            createdAt: try ATATimestampCodec.decode(dto.createdAt),
            updatedAt: try ATATimestampCodec.decode(dto.updatedAt),
            resolvedAt: try dto.resolvedAt.map { try ATATimestampCodec.decode($0) }
        )
    }

    static func domain(from dto: ATACurrentPortfolioDTO) throws -> ATACurrentPortfolio {
        guard dto.revision > 0 else { throw ATAWireError.invalidValue }
        return ATACurrentPortfolio(
            revision: dto.revision,
            snapshotID: try identity(dto.snapshotID),
            confirmedAt: try ATATimestampCodec.decode(dto.confirmedAt),
            accounts: try dto.accounts.map { try domain(from: $0) },
            aggregatePositions: try dto.aggregatePositions.map { try domain(from: $0) },
            financialSettings: try domain(from: dto.financialSettings),
            corePositions: try dto.corePositions.map { try domain(from: $0) },
            limitOrders: try dto.limitOrders.map { try domain(from: $0) }
        )
    }
}
