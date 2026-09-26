import Foundation

// Request-only DTOs: typed construction, exact financial strings, no HTTP behavior.
// OrderLifecycle is the identical body for the separate cancel and expire endpoints.
// Holdings and confirm-filled always carry the complete resulting account positions.
struct ATAPositionInputDTO: Encodable, Equatable, Sendable {
    let symbol: String
    let amount: String

    init(_ position: ATAPosition) throws {
        symbol = position.symbol.rawValue
        amount = try ATAMutationInput.positive(position.amount)
    }
}

struct ATACreateAccountRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int
    let name: String
    let accountType: String
    let positions: [ATAPositionInputDTO]

    init(expectedRevision: Int, name: String, accountType: ATAAccountType, positions: [ATAPosition])
        throws
    {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
        self.name = try ATAMutationInput.name(name)
        self.accountType = accountType.rawValue
        self.positions = try ATAMutationInput.positions(positions)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case name = "name"
        case accountType = "account_type"
        case positions = "positions"
    }
}

struct ATARenameAccountRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int
    let name: String

    init(expectedRevision: Int, name: String) throws {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
        self.name = try ATAMutationInput.name(name)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case name = "name"
    }
}

struct ATAReplaceAccountHoldingsRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int
    let positions: [ATAPositionInputDTO]

    init(expectedRevision: Int, positions: [ATAPosition]) throws {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
        self.positions = try ATAMutationInput.positions(positions)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case positions = "positions"
    }
}

struct ATADeleteAccountRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int

    init(expectedRevision: Int) throws {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
    }
}

struct ATAUpdateFinancialSettingsRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int
    let monthlyExpensesUSD: String
    let targetExpenseRunwayMonths: String

    init(expectedRevision: Int, monthlyExpensesUSD: Decimal, targetExpenseRunwayMonths: Decimal)
        throws
    {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
        self.monthlyExpensesUSD = try ATAMutationInput.positive(monthlyExpensesUSD)
        self.targetExpenseRunwayMonths = try ATAMutationInput.positive(targetExpenseRunwayMonths)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case monthlyExpensesUSD = "monthly_expenses_usd"
        case targetExpenseRunwayMonths = "target_expense_runway_months"
    }
}

struct ATAUpdateCorePositionRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int
    let hardFloor: String
    let preferredQuantity: String

    init(expectedRevision: Int, hardFloor: Decimal, preferredQuantity: Decimal) throws {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
        self.hardFloor = try ATAMutationInput.positive(hardFloor)
        self.preferredQuantity = try ATAMutationInput.positive(preferredQuantity)
        guard preferredQuantity >= hardFloor else { throw ATAWireError.invalidValue }
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case hardFloor = "hard_floor"
        case preferredQuantity = "preferred_quantity"
    }
}

struct ATACreateOrderRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int
    let accountID: String
    let asset: String
    let side: String
    let targetPrice: String
    let quantityAsset: String

    init(
        expectedRevision: Int, accountID: UUID, asset: AssetSymbol, side: ATAOrderSide,
        targetPrice: Decimal, quantityAsset: Decimal
    ) throws {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
        self.accountID = try ATAResponseMapper.identity(accountID.uuidString).uuidString
            .lowercased()
        self.asset = asset.rawValue
        self.side = side.rawValue
        self.targetPrice = try ATAMutationInput.positive(targetPrice)
        self.quantityAsset = try ATAMutationInput.positive(quantityAsset)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case accountID = "account_id"
        case asset = "asset"
        case side = "side"
        case targetPrice = "target_price"
        case quantityAsset = "quantity_asset"
    }
}

struct ATAOrderLifecycleRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int

    init(expectedRevision: Int) throws {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
    }
}

struct ATAConfirmOrderFilledRequestDTO: Encodable, Equatable, Sendable {
    let expectedRevision: Int
    let settlementAsset: String
    let positions: [ATAPositionInputDTO]

    init(expectedRevision: Int, settlementAsset: AssetSymbol, positions: [ATAPosition]) throws {
        self.expectedRevision = try ATAMutationInput.revision(expectedRevision)
        guard settlementAsset == .usdt || settlementAsset == .usdc else {
            throw ATAWireError.invalidValue
        }
        self.settlementAsset = settlementAsset.rawValue
        self.positions = try ATAMutationInput.positions(positions)
    }

    private enum CodingKeys: String, CodingKey {
        case expectedRevision = "expected_revision"
        case settlementAsset = "settlement_asset"
        case positions = "positions"
    }
}

private enum ATAMutationInput {
    static func revision(_ value: Int) throws -> Int {
        guard value > 0 else { throw ATAWireError.invalidValue }
        return value
    }

    static func name(_ value: String) throws -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ATAWireError.invalidValue
        }
        return value
    }

    static func positive(_ value: Decimal) throws -> String {
        guard !value.isNaN, value > 0 else { throw ATAWireError.invalidValue }
        return try ATADecimalCodec.encode(value)
    }

    static func positions(_ values: [ATAPosition]) throws -> [ATAPositionInputDTO] {
        guard Set(values.map(\.symbol)).count == values.count else {
            throw ATAWireError.invalidValue
        }
        return try values.map(ATAPositionInputDTO.init)
    }
}
