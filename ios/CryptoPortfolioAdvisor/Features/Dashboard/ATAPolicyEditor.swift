import Foundation

// Transient text only. The loaded server portfolio remains the confirmed policy state.
struct ATAPolicyEditor: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case financialSettings
        case corePosition(AssetSymbol)
    }

    enum InputError: Error, Equatable, Sendable {
        case monthlyExpenses
        case targetRunway
        case hardFloor
        case preferredQuantity
        case preferredBelowFloor
        case floorExceedsHoldings
        case unsupportedCorePolicy
        case policyMissing
        case unchanged
    }

    let kind: Kind
    var firstValue: String
    var secondValue: String
    let policyVersion: Int?
    var inputError: InputError?
    var needsReview = false

    init(financialSettings: ATAFinancialSettings) throws {
        kind = .financialSettings
        firstValue = try ATADecimalCodec.encode(financialSettings.monthlyExpensesUSD)
        secondValue = try ATADecimalCodec.encode(financialSettings.targetExpenseRunwayMonths)
        policyVersion = nil
    }

    init(corePosition: ATACorePosition) throws {
        kind = .corePosition(corePosition.symbol)
        firstValue = try ATADecimalCodec.encode(corePosition.hardFloor)
        secondValue = try ATADecimalCodec.encode(corePosition.preferredQuantity)
        policyVersion = corePosition.policyVersion
    }

    func financialValues() throws -> (monthlyExpensesUSD: Decimal, targetRunwayMonths: Decimal) {
        let monthly = try positive(firstValue, error: .monthlyExpenses)
        let runway = try positive(secondValue, error: .targetRunway)
        return (monthly, runway)
    }

    func coreValues(aggregateAmount: Decimal) throws -> (
        hardFloor: Decimal, preferredQuantity: Decimal
    ) {
        guard case .corePosition(let symbol) = kind,
            symbol == .btc || symbol == .eth || symbol == .sol,
            policyVersion == 1
        else { throw InputError.unsupportedCorePolicy }
        let floor = try positive(firstValue, error: .hardFloor)
        let preferred = try positive(secondValue, error: .preferredQuantity)
        guard preferred >= floor else { throw InputError.preferredBelowFloor }
        guard floor <= aggregateAmount else { throw InputError.floorExceedsHoldings }
        return (floor, preferred)
    }

    private func positive(_ text: String, error: InputError) throws -> Decimal {
        guard let value = try? ATADecimalCodec.decode(text), value > 0 else { throw error }
        return value
    }
}
