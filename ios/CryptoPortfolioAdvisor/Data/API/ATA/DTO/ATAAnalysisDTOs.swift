import Foundation

// Frozen ATA V1 wire shapes. Nullable response fields are required keys.

struct ATAAnalysisRunDTO: Decodable, Equatable, Sendable {
    let runID: String
    let snapshotID: String
    let startedAt: String
    let status: String
    let completedAt: String?
    let marketCutoff: String?

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case snapshotID = "snapshot_id"
        case startedAt = "started_at"
        case status = "status"
        case completedAt = "completed_at"
        case marketCutoff = "market_cutoff"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runID = try c.decode(String.self, forKey: .runID)
        snapshotID = try c.decode(String.self, forKey: .snapshotID)
        startedAt = try c.decode(String.self, forKey: .startedAt)
        status = try c.decode(String.self, forKey: .status)
        completedAt = try c.decode(String?.self, forKey: .completedAt)
        marketCutoff = try c.decode(String?.self, forKey: .marketCutoff)
    }
}

struct ATARecentAnalysesDTO: Decodable, Equatable, Sendable {
    let analyses: [ATAAnalysisRunDTO]

    private enum CodingKeys: String, CodingKey {
        case analyses = "analyses"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        analyses = try c.decode([ATAAnalysisRunDTO].self, forKey: .analyses)
    }
}

struct ATACandleDTO: Decodable, Equatable, Sendable {
    let closedAt: String
    let open: String
    let high: String
    let low: String
    let close: String

    private enum CodingKeys: String, CodingKey {
        case closedAt = "closed_at"
        case open = "open"
        case high = "high"
        case low = "low"
        case close = "close"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        closedAt = try c.decode(String.self, forKey: .closedAt)
        open = try c.decode(String.self, forKey: .open)
        high = try c.decode(String.self, forKey: .high)
        low = try c.decode(String.self, forKey: .low)
        close = try c.decode(String.self, forKey: .close)
    }
}

struct ATATechnicalFeaturesDTO: Decodable, Equatable, Sendable {
    let change24hPct: String?
    let change7dPct: String?
    let rsi4H: String?
    let ema204H: String?
    let ema504H: String?
    let atr4H: String?
    let support: String?
    let resistance: String?

    private enum CodingKeys: String, CodingKey {
        case change24hPct = "change_24h_pct"
        case change7dPct = "change_7d_pct"
        case rsi4H = "rsi_4h"
        case ema204H = "ema20_4h"
        case ema504H = "ema50_4h"
        case atr4H = "atr_4h"
        case support = "support"
        case resistance = "resistance"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        change24hPct = try c.decode(String?.self, forKey: .change24hPct)
        change7dPct = try c.decode(String?.self, forKey: .change7dPct)
        rsi4H = try c.decode(String?.self, forKey: .rsi4H)
        ema204H = try c.decode(String?.self, forKey: .ema204H)
        ema504H = try c.decode(String?.self, forKey: .ema504H)
        atr4H = try c.decode(String?.self, forKey: .atr4H)
        support = try c.decode(String?.self, forKey: .support)
        resistance = try c.decode(String?.self, forKey: .resistance)
    }
}

struct ATADailyContextDTO: Decodable, Equatable, Sendable {
    let latestClosedAt: String?
    let closedPriceUSD: String?
    let ema20: String?
    let ema50: String?
    let support: String?
    let resistance: String?
    let trend: String

    private enum CodingKeys: String, CodingKey {
        case latestClosedAt = "latest_closed_at"
        case closedPriceUSD = "closed_price_usd"
        case ema20 = "ema20"
        case ema50 = "ema50"
        case support = "support"
        case resistance = "resistance"
        case trend = "trend"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latestClosedAt = try c.decode(String?.self, forKey: .latestClosedAt)
        closedPriceUSD = try c.decode(String?.self, forKey: .closedPriceUSD)
        ema20 = try c.decode(String?.self, forKey: .ema20)
        ema50 = try c.decode(String?.self, forKey: .ema50)
        support = try c.decode(String?.self, forKey: .support)
        resistance = try c.decode(String?.self, forKey: .resistance)
        trend = try c.decode(String.self, forKey: .trend)
    }
}

struct ATAMarketAssetDTO: Decodable, Equatable, Sendable {
    let symbol: String
    let priceUSD: String
    let quotedAt: String
    let latestClosedCandleAt: String?
    let technicalFeatures: ATATechnicalFeaturesDTO
    let completeness: String
    let latestClosedPriceUSD: String?
    let dailyContext: ATADailyContextDTO
    let closed1HCandles: [ATACandleDTO]

    private enum CodingKeys: String, CodingKey {
        case symbol = "symbol"
        case priceUSD = "price_usd"
        case quotedAt = "quoted_at"
        case latestClosedCandleAt = "latest_closed_candle_at"
        case technicalFeatures = "technical_features"
        case completeness = "completeness"
        case latestClosedPriceUSD = "latest_closed_price_usd"
        case dailyContext = "daily_context"
        case closed1HCandles = "closed_1h_candles"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        priceUSD = try c.decode(String.self, forKey: .priceUSD)
        quotedAt = try c.decode(String.self, forKey: .quotedAt)
        latestClosedCandleAt = try c.decode(String?.self, forKey: .latestClosedCandleAt)
        technicalFeatures = try c.decode(ATATechnicalFeaturesDTO.self, forKey: .technicalFeatures)
        completeness = try c.decode(String.self, forKey: .completeness)
        latestClosedPriceUSD = try c.decode(String?.self, forKey: .latestClosedPriceUSD)
        dailyContext = try c.decode(ATADailyContextDTO.self, forKey: .dailyContext)
        closed1HCandles = try c.decode([ATACandleDTO].self, forKey: .closed1HCandles)
    }
}

struct ATAMarketSnapshotDTO: Decodable, Equatable, Sendable {
    let asOf: String
    let assets: [ATAMarketAssetDTO]
    let isLive: Bool

    private enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case assets = "assets"
        case isLive = "is_live"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOf = try c.decode(String.self, forKey: .asOf)
        assets = try c.decode([ATAMarketAssetDTO].self, forKey: .assets)
        isLive = try c.decode(Bool.self, forKey: .isLive)
    }
}

struct ATAFinancialSummaryDTO: Decodable, Equatable, Sendable {
    let totalPortfolioUSD: String
    let currentStablesUSD: String
    let stableAllocationPercent: String
    let monthlyExpensesUSD: String
    let targetExpenseRunwayMonths: String
    let recommendedMinimumStablesUSD: String
    let deployableStablesUSD: String
    let stableReserveDeficitUSD: String
    let actualExpenseRunwayMonths: String
    let openBuyCommitmentsUSD: String
    let hardExpenseReserveUSD: String
    let marketBufferUSD: String
    let potentialTradingLiquidityUSD: String
    let strategyDryPowderUSD: String
    let recommendedDeploymentUSD: String

    private enum CodingKeys: String, CodingKey {
        case totalPortfolioUSD = "total_portfolio_usd"
        case currentStablesUSD = "current_stables_usd"
        case stableAllocationPercent = "stable_allocation_percent"
        case monthlyExpensesUSD = "monthly_expenses_usd"
        case targetExpenseRunwayMonths = "target_expense_runway_months"
        case recommendedMinimumStablesUSD = "recommended_minimum_stables_usd"
        case deployableStablesUSD = "deployable_stables_usd"
        case stableReserveDeficitUSD = "stable_reserve_deficit_usd"
        case actualExpenseRunwayMonths = "actual_expense_runway_months"
        case openBuyCommitmentsUSD = "open_buy_commitments_usd"
        case hardExpenseReserveUSD = "hard_expense_reserve_usd"
        case marketBufferUSD = "market_buffer_usd"
        case potentialTradingLiquidityUSD = "potential_trading_liquidity_usd"
        case strategyDryPowderUSD = "strategy_dry_powder_usd"
        case recommendedDeploymentUSD = "recommended_deployment_usd"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalPortfolioUSD = try c.decode(String.self, forKey: .totalPortfolioUSD)
        currentStablesUSD = try c.decode(String.self, forKey: .currentStablesUSD)
        stableAllocationPercent = try c.decode(String.self, forKey: .stableAllocationPercent)
        monthlyExpensesUSD = try c.decode(String.self, forKey: .monthlyExpensesUSD)
        targetExpenseRunwayMonths = try c.decode(String.self, forKey: .targetExpenseRunwayMonths)
        recommendedMinimumStablesUSD = try c.decode(
            String.self, forKey: .recommendedMinimumStablesUSD)
        deployableStablesUSD = try c.decode(String.self, forKey: .deployableStablesUSD)
        stableReserveDeficitUSD = try c.decode(String.self, forKey: .stableReserveDeficitUSD)
        actualExpenseRunwayMonths = try c.decode(String.self, forKey: .actualExpenseRunwayMonths)
        openBuyCommitmentsUSD = try c.decode(String.self, forKey: .openBuyCommitmentsUSD)
        hardExpenseReserveUSD = try c.decode(String.self, forKey: .hardExpenseReserveUSD)
        marketBufferUSD = try c.decode(String.self, forKey: .marketBufferUSD)
        potentialTradingLiquidityUSD = try c.decode(
            String.self, forKey: .potentialTradingLiquidityUSD)
        strategyDryPowderUSD = try c.decode(String.self, forKey: .strategyDryPowderUSD)
        recommendedDeploymentUSD = try c.decode(String.self, forKey: .recommendedDeploymentUSD)
    }
}

struct ATARecommendationDTO: Decodable, Equatable, Sendable {
    let recommendationID: String
    let asset: String?
    let actionType: String
    let priority: Int
    let reason: String
    let existingOrderID: String?
    let side: String?
    let targetPrice: String?
    let quantityAsset: String?
    let invalidationCondition: String?
    let reviewAt: String?
    let expiresAt: String?
    let setupID: String?

    private enum CodingKeys: String, CodingKey {
        case recommendationID = "recommendation_id"
        case asset = "asset"
        case actionType = "action_type"
        case priority = "priority"
        case reason = "reason"
        case existingOrderID = "existing_order_id"
        case side = "side"
        case targetPrice = "target_price"
        case quantityAsset = "quantity_asset"
        case invalidationCondition = "invalidation_condition"
        case reviewAt = "review_at"
        case expiresAt = "expires_at"
        case setupID = "setup_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recommendationID = try c.decode(String.self, forKey: .recommendationID)
        asset = try c.decode(String?.self, forKey: .asset)
        actionType = try c.decode(String.self, forKey: .actionType)
        priority = try c.decode(Int.self, forKey: .priority)
        reason = try c.decode(String.self, forKey: .reason)
        existingOrderID = try c.decode(String?.self, forKey: .existingOrderID)
        side = try c.decode(String?.self, forKey: .side)
        targetPrice = try c.decode(String?.self, forKey: .targetPrice)
        quantityAsset = try c.decode(String?.self, forKey: .quantityAsset)
        invalidationCondition = try c.decode(String?.self, forKey: .invalidationCondition)
        reviewAt = try c.decode(String?.self, forKey: .reviewAt)
        expiresAt = try c.decode(String?.self, forKey: .expiresAt)
        setupID = try c.decode(String?.self, forKey: .setupID)
    }
}

struct ATADecisionConfigurationDTO: Decodable, Equatable, Sendable {
    let marketRegimeVersion: Int
    let stableReserveVersion: Int
    let wholePlanVersion: Int
    let targetRunwayMonths: String
    let marketSource: String
    let aiEnabled: Bool
    let modelName: String?
    let reasoningEffort: String?
    let aiContextVersion: Int?
    let aiSchemaVersion: Int?
    let aiPromptVersion: Int?
    let aiFailureCategory: String?
    let recommendationParameters: String
    let activePolicyParameters: String?
    let reservePolicyParameters: String?

    private enum CodingKeys: String, CodingKey {
        case marketRegimeVersion = "market_regime_version"
        case stableReserveVersion = "stable_reserve_version"
        case wholePlanVersion = "whole_plan_version"
        case targetRunwayMonths = "target_runway_months"
        case marketSource = "market_source"
        case aiEnabled = "ai_enabled"
        case modelName = "model_name"
        case reasoningEffort = "reasoning_effort"
        case aiContextVersion = "ai_context_version"
        case aiSchemaVersion = "ai_schema_version"
        case aiPromptVersion = "ai_prompt_version"
        case aiFailureCategory = "ai_failure_category"
        case recommendationParameters = "recommendation_parameters"
        case activePolicyParameters = "active_policy_parameters"
        case reservePolicyParameters = "reserve_policy_parameters"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        marketRegimeVersion = try c.decode(Int.self, forKey: .marketRegimeVersion)
        stableReserveVersion = try c.decode(Int.self, forKey: .stableReserveVersion)
        wholePlanVersion = try c.decode(Int.self, forKey: .wholePlanVersion)
        targetRunwayMonths = try c.decode(String.self, forKey: .targetRunwayMonths)
        marketSource = try c.decode(String.self, forKey: .marketSource)
        aiEnabled = try c.decode(Bool.self, forKey: .aiEnabled)
        modelName = try c.decode(String?.self, forKey: .modelName)
        reasoningEffort = try c.decode(String?.self, forKey: .reasoningEffort)
        aiContextVersion = try c.decode(Int?.self, forKey: .aiContextVersion)
        aiSchemaVersion = try c.decode(Int?.self, forKey: .aiSchemaVersion)
        aiPromptVersion = try c.decode(Int?.self, forKey: .aiPromptVersion)
        aiFailureCategory = try c.decode(String?.self, forKey: .aiFailureCategory)
        recommendationParameters = try c.decode(String.self, forKey: .recommendationParameters)
        activePolicyParameters = try c.decode(String?.self, forKey: .activePolicyParameters)
        reservePolicyParameters = try c.decode(String?.self, forKey: .reservePolicyParameters)
    }
}

struct ATASetupLevelDTO: Decodable, Equatable, Sendable {
    let price: String
    let source: String
    let priority: Int

    private enum CodingKeys: String, CodingKey {
        case price = "price"
        case source = "source"
        case priority = "priority"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        price = try c.decode(String.self, forKey: .price)
        source = try c.decode(String.self, forKey: .source)
        priority = try c.decode(Int.self, forKey: .priority)
    }
}

struct ATASetupScoreDTO: Decodable, Equatable, Sendable {
    let version: Int
    let components: [ATAScoreComponentDTO]

    private enum CodingKeys: String, CodingKey {
        case version = "version"
        case components = "components"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        components = try c.decode([ATAScoreComponentDTO].self, forKey: .components)
    }
}

struct ATATriggerTransitionDTO: Decodable, Equatable, Sendable {
    let previousState: String
    let currentState: String
    let transitionedAt: String
    let marketCutoff: String
    let timeframe: String
    let reason: String
    let referencePrice: String

    private enum CodingKeys: String, CodingKey {
        case previousState = "previous_state"
        case currentState = "current_state"
        case transitionedAt = "transitioned_at"
        case marketCutoff = "market_cutoff"
        case timeframe = "timeframe"
        case reason = "reason"
        case referencePrice = "reference_price"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        previousState = try c.decode(String.self, forKey: .previousState)
        currentState = try c.decode(String.self, forKey: .currentState)
        transitionedAt = try c.decode(String.self, forKey: .transitionedAt)
        marketCutoff = try c.decode(String.self, forKey: .marketCutoff)
        timeframe = try c.decode(String.self, forKey: .timeframe)
        reason = try c.decode(String.self, forKey: .reason)
        referencePrice = try c.decode(String.self, forKey: .referencePrice)
    }
}

struct ATATriggerContextDTO: Decodable, Equatable, Sendable {
    let version: Int
    let zoneLow: String
    let zoneHigh: String
    let atrAtCreation: String
    let transitions: [ATATriggerTransitionDTO]
    let touchedAt: String?
    let highestObservedPrice: String?
    let lowestObservedPrice: String?
    let triggerReferencePrice: String?
    let confirmationAt: String?
    let confirmationCandle: ATACandleDTO?
    let expiresAt: String?
    let lastProcessed1HCandleAt: String?
    let executionValid: Bool

    private enum CodingKeys: String, CodingKey {
        case version = "version"
        case zoneLow = "zone_low"
        case zoneHigh = "zone_high"
        case atrAtCreation = "atr_at_creation"
        case transitions = "transitions"
        case touchedAt = "touched_at"
        case highestObservedPrice = "highest_observed_price"
        case lowestObservedPrice = "lowest_observed_price"
        case triggerReferencePrice = "trigger_reference_price"
        case confirmationAt = "confirmation_at"
        case confirmationCandle = "confirmation_candle"
        case expiresAt = "expires_at"
        case lastProcessed1HCandleAt = "last_processed_1h_candle_at"
        case executionValid = "execution_valid"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        zoneLow = try c.decode(String.self, forKey: .zoneLow)
        zoneHigh = try c.decode(String.self, forKey: .zoneHigh)
        atrAtCreation = try c.decode(String.self, forKey: .atrAtCreation)
        transitions = try c.decode([ATATriggerTransitionDTO].self, forKey: .transitions)
        touchedAt = try c.decode(String?.self, forKey: .touchedAt)
        highestObservedPrice = try c.decode(String?.self, forKey: .highestObservedPrice)
        lowestObservedPrice = try c.decode(String?.self, forKey: .lowestObservedPrice)
        triggerReferencePrice = try c.decode(String?.self, forKey: .triggerReferencePrice)
        confirmationAt = try c.decode(String?.self, forKey: .confirmationAt)
        confirmationCandle = try c.decode(ATACandleDTO?.self, forKey: .confirmationCandle)
        expiresAt = try c.decode(String?.self, forKey: .expiresAt)
        lastProcessed1HCandleAt = try c.decode(String?.self, forKey: .lastProcessed1HCandleAt)
        executionValid = try c.decode(Bool.self, forKey: .executionValid)
    }
}

struct ATATradeSetupDTO: Decodable, Equatable, Sendable {
    let id: String
    let asset: String
    let direction: String
    let setupType: String
    let createdAt: String
    let originatingCutoff: String
    let status: String
    let limitPrice: String
    let priceSource: String
    let invalidationPrice: String
    let invalidationSource: String
    let targetPrice: String
    let targetSource: String
    let riskReward: String
    let maximumCapitalUSD: String
    let score: ATASetupScoreDTO
    let relatedOrderIDs: [String]
    let levels: [ATASetupLevelDTO]
    let trigger: ATATriggerContextDTO?

    private enum CodingKeys: String, CodingKey {
        case id = "id"
        case asset = "asset"
        case direction = "direction"
        case setupType = "setup_type"
        case createdAt = "created_at"
        case originatingCutoff = "originating_cutoff"
        case status = "status"
        case limitPrice = "limit_price"
        case priceSource = "price_source"
        case invalidationPrice = "invalidation_price"
        case invalidationSource = "invalidation_source"
        case targetPrice = "target_price"
        case targetSource = "target_source"
        case riskReward = "risk_reward"
        case maximumCapitalUSD = "maximum_capital_usd"
        case score = "score"
        case relatedOrderIDs = "related_order_ids"
        case levels = "levels"
        case trigger = "trigger"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        asset = try c.decode(String.self, forKey: .asset)
        direction = try c.decode(String.self, forKey: .direction)
        setupType = try c.decode(String.self, forKey: .setupType)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        originatingCutoff = try c.decode(String.self, forKey: .originatingCutoff)
        status = try c.decode(String.self, forKey: .status)
        limitPrice = try c.decode(String.self, forKey: .limitPrice)
        priceSource = try c.decode(String.self, forKey: .priceSource)
        invalidationPrice = try c.decode(String.self, forKey: .invalidationPrice)
        invalidationSource = try c.decode(String.self, forKey: .invalidationSource)
        targetPrice = try c.decode(String.self, forKey: .targetPrice)
        targetSource = try c.decode(String.self, forKey: .targetSource)
        riskReward = try c.decode(String.self, forKey: .riskReward)
        maximumCapitalUSD = try c.decode(String.self, forKey: .maximumCapitalUSD)
        score = try c.decode(ATASetupScoreDTO.self, forKey: .score)
        relatedOrderIDs = try c.decode([String].self, forKey: .relatedOrderIDs)
        levels = try c.decode([ATASetupLevelDTO].self, forKey: .levels)
        trigger = try c.decode(ATATriggerContextDTO?.self, forKey: .trigger)
    }
}

struct ATAAssetDecisionDTO: Decodable, Equatable, Sendable {
    let asset: String
    let decision: String
    let quantity: String
    let marketValueUSD: String
    let allocationPercent: String
    let coreFloor: String?
    let preferredCore: String?
    let tradableQuantity: String
    let dailyTrend: String
    let setupID: String?

    private enum CodingKeys: String, CodingKey {
        case asset = "asset"
        case decision = "decision"
        case quantity = "quantity"
        case marketValueUSD = "market_value_usd"
        case allocationPercent = "allocation_percent"
        case coreFloor = "core_floor"
        case preferredCore = "preferred_core"
        case tradableQuantity = "tradable_quantity"
        case dailyTrend = "daily_trend"
        case setupID = "setup_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asset = try c.decode(String.self, forKey: .asset)
        decision = try c.decode(String.self, forKey: .decision)
        quantity = try c.decode(String.self, forKey: .quantity)
        marketValueUSD = try c.decode(String.self, forKey: .marketValueUSD)
        allocationPercent = try c.decode(String.self, forKey: .allocationPercent)
        coreFloor = try c.decode(String?.self, forKey: .coreFloor)
        preferredCore = try c.decode(String?.self, forKey: .preferredCore)
        tradableQuantity = try c.decode(String.self, forKey: .tradableQuantity)
        dailyTrend = try c.decode(String.self, forKey: .dailyTrend)
        setupID = try c.decode(String?.self, forKey: .setupID)
    }
}

struct ATAActiveAnalysisDTO: Decodable, Equatable, Sendable {
    let policyVersion: Int
    let setups: [ATATradeSetupDTO]
    let assetDecisions: [ATAAssetDecisionDTO]
    let rankedSetupIDs: [String]
    let recommendedDeploymentUSD: String
    let strategyDryPowderUSD: String
    let severity: String

    private enum CodingKeys: String, CodingKey {
        case policyVersion = "policy_version"
        case setups = "setups"
        case assetDecisions = "asset_decisions"
        case rankedSetupIDs = "ranked_setup_ids"
        case recommendedDeploymentUSD = "recommended_deployment_usd"
        case strategyDryPowderUSD = "strategy_dry_powder_usd"
        case severity = "severity"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        policyVersion = try c.decode(Int.self, forKey: .policyVersion)
        setups = try c.decode([ATATradeSetupDTO].self, forKey: .setups)
        assetDecisions = try c.decode([ATAAssetDecisionDTO].self, forKey: .assetDecisions)
        rankedSetupIDs = try c.decode([String].self, forKey: .rankedSetupIDs)
        recommendedDeploymentUSD = try c.decode(String.self, forKey: .recommendedDeploymentUSD)
        strategyDryPowderUSD = try c.decode(String.self, forKey: .strategyDryPowderUSD)
        severity = try c.decode(String.self, forKey: .severity)
    }
}

struct ATAAnalysisResultDTO: Decodable, Equatable, Sendable {
    let runID: String
    let snapshotID: String
    let generatedAt: String
    let marketCutoff: String?
    let market: ATAMarketSnapshotDTO
    let marketRegime: String
    let regimePolicyVersion: Int
    let recommendationPolicyVersion: Int
    let financial: ATAFinancialSummaryDTO
    let warnings: [String]
    let recommendations: [ATARecommendationDTO]
    let reasoningMode: String
    let reasoningModel: String?
    let aiWarning: String?
    let configuration: ATADecisionConfigurationDTO?
    let active: ATAActiveAnalysisDTO?

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case snapshotID = "snapshot_id"
        case generatedAt = "generated_at"
        case marketCutoff = "market_cutoff"
        case market = "market"
        case marketRegime = "market_regime"
        case regimePolicyVersion = "regime_policy_version"
        case recommendationPolicyVersion = "recommendation_policy_version"
        case financial = "financial"
        case warnings = "warnings"
        case recommendations = "recommendations"
        case reasoningMode = "reasoning_mode"
        case reasoningModel = "reasoning_model"
        case aiWarning = "ai_warning"
        case configuration = "configuration"
        case active = "active"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runID = try c.decode(String.self, forKey: .runID)
        snapshotID = try c.decode(String.self, forKey: .snapshotID)
        generatedAt = try c.decode(String.self, forKey: .generatedAt)
        marketCutoff = try c.decode(String?.self, forKey: .marketCutoff)
        market = try c.decode(ATAMarketSnapshotDTO.self, forKey: .market)
        marketRegime = try c.decode(String.self, forKey: .marketRegime)
        regimePolicyVersion = try c.decode(Int.self, forKey: .regimePolicyVersion)
        recommendationPolicyVersion = try c.decode(Int.self, forKey: .recommendationPolicyVersion)
        financial = try c.decode(ATAFinancialSummaryDTO.self, forKey: .financial)
        warnings = try c.decode([String].self, forKey: .warnings)
        recommendations = try c.decode([ATARecommendationDTO].self, forKey: .recommendations)
        reasoningMode = try c.decode(String.self, forKey: .reasoningMode)
        reasoningModel = try c.decode(String?.self, forKey: .reasoningModel)
        aiWarning = try c.decode(String?.self, forKey: .aiWarning)
        configuration = try c.decode(ATADecisionConfigurationDTO?.self, forKey: .configuration)
        active = try c.decode(ATAActiveAnalysisDTO?.self, forKey: .active)
    }
}

struct ATAAnalysisDetailDTO: Decodable, Equatable, Sendable {
    let run: ATAAnalysisRunDTO
    let result: ATAAnalysisResultDTO?
    let failureCategory: String?

    private enum CodingKeys: String, CodingKey {
        case run = "run"
        case result = "result"
        case failureCategory = "failure_category"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try c.decode(ATAAnalysisRunDTO.self, forKey: .run)
        result = try c.decode(ATAAnalysisResultDTO?.self, forKey: .result)
        failureCategory = try c.decode(String?.self, forKey: .failureCategory)
    }
}
