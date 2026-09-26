import Foundation

// Frozen ATA V1 wire shapes. Nullable response fields are required keys.

struct ATAPositionDTO: Decodable, Equatable, Sendable {
    let symbol: String
    let amount: String

    private enum CodingKeys: String, CodingKey {
        case symbol = "symbol"
        case amount = "amount"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        amount = try c.decode(String.self, forKey: .amount)
    }
}

struct ATAAccountDTO: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let positions: [ATAPositionDTO]

    private enum CodingKeys: String, CodingKey {
        case id = "id"
        case name = "name"
        case type = "type"
        case positions = "positions"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(String.self, forKey: .type)
        positions = try c.decode([ATAPositionDTO].self, forKey: .positions)
    }
}

struct ATAFinancialSettingsDTO: Decodable, Equatable, Sendable {
    let monthlyExpensesUSD: String
    let targetExpenseRunwayMonths: String

    private enum CodingKeys: String, CodingKey {
        case monthlyExpensesUSD = "monthly_expenses_usd"
        case targetExpenseRunwayMonths = "target_expense_runway_months"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthlyExpensesUSD = try c.decode(String.self, forKey: .monthlyExpensesUSD)
        targetExpenseRunwayMonths = try c.decode(String.self, forKey: .targetExpenseRunwayMonths)
    }
}

struct ATACorePositionDTO: Decodable, Equatable, Sendable {
    let symbol: String
    let hardFloor: String
    let preferredQuantity: String
    let policyVersion: Int

    private enum CodingKeys: String, CodingKey {
        case symbol = "symbol"
        case hardFloor = "hard_floor"
        case preferredQuantity = "preferred_quantity"
        case policyVersion = "policy_version"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        hardFloor = try c.decode(String.self, forKey: .hardFloor)
        preferredQuantity = try c.decode(String.self, forKey: .preferredQuantity)
        policyVersion = try c.decode(Int.self, forKey: .policyVersion)
    }
}

struct ATALimitOrderDTO: Decodable, Equatable, Sendable {
    let id: String
    let accountID: String
    let asset: String
    let side: String
    let targetPrice: String
    let quantityAsset: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let resolvedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id = "id"
        case accountID = "account_id"
        case asset = "asset"
        case side = "side"
        case targetPrice = "target_price"
        case quantityAsset = "quantity_asset"
        case status = "status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case resolvedAt = "resolved_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        accountID = try c.decode(String.self, forKey: .accountID)
        asset = try c.decode(String.self, forKey: .asset)
        side = try c.decode(String.self, forKey: .side)
        targetPrice = try c.decode(String.self, forKey: .targetPrice)
        quantityAsset = try c.decode(String.self, forKey: .quantityAsset)
        status = try c.decode(String.self, forKey: .status)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        resolvedAt = try c.decode(String?.self, forKey: .resolvedAt)
    }
}

struct ATACurrentPortfolioDTO: Decodable, Equatable, Sendable {
    let revision: Int
    let snapshotID: String
    let confirmedAt: String
    let accounts: [ATAAccountDTO]
    let aggregatePositions: [ATAPositionDTO]
    let financialSettings: ATAFinancialSettingsDTO
    let corePositions: [ATACorePositionDTO]
    let limitOrders: [ATALimitOrderDTO]

    private enum CodingKeys: String, CodingKey {
        case revision = "revision"
        case snapshotID = "snapshot_id"
        case confirmedAt = "confirmed_at"
        case accounts = "accounts"
        case aggregatePositions = "aggregate_positions"
        case financialSettings = "financial_settings"
        case corePositions = "core_positions"
        case limitOrders = "limit_orders"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decode(Int.self, forKey: .revision)
        snapshotID = try c.decode(String.self, forKey: .snapshotID)
        confirmedAt = try c.decode(String.self, forKey: .confirmedAt)
        accounts = try c.decode([ATAAccountDTO].self, forKey: .accounts)
        aggregatePositions = try c.decode([ATAPositionDTO].self, forKey: .aggregatePositions)
        financialSettings = try c.decode(ATAFinancialSettingsDTO.self, forKey: .financialSettings)
        corePositions = try c.decode([ATACorePositionDTO].self, forKey: .corePositions)
        limitOrders = try c.decode([ATALimitOrderDTO].self, forKey: .limitOrders)
    }
}
