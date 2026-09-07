import Foundation

enum PersistenceMappingError: Error, Equatable, Sendable {
    case invalidDecimal(String)
}

enum PersistenceMapper {
    static func encodeDashboardDraft(_ draft: PersistedDashboardDraft) throws -> Data {
        try JSONEncoder().encode(draft)
    }

    static func decodeDashboardDraft(_ data: Data) throws -> PersistedDashboardDraft {
        try JSONDecoder().decode(PersistedDashboardDraft.self, from: data)
    }

    static func encodeSnapshot(_ snapshot: PortfolioSnapshot) throws -> Data {
        let persistedSnapshot = PersistedPortfolioSnapshot(
            positions: snapshot.portfolio.positions.map {
                PersistedSnapshotPosition(
                    symbol: $0.symbol.rawValue,
                    amount: canonicalString(for: $0.amount)
                )
            },
            constraints: PersistedSnapshotConstraints(
                tradingStyle: snapshot.constraints.tradingStyle,
                riskTolerance: snapshot.constraints.riskTolerance,
                leverageAllowed: snapshot.constraints.leverageAllowed,
                additionalMonthlyIncomeUSD: canonicalString(
                    for: snapshot.constraints.additionalMonthlyIncomeUSD
                ),
                minimumStableReserveUSD: canonicalString(
                    for: snapshot.constraints.minimumStableReserveUSD
                )
            ),
            orders: snapshot.orders.map {
                PersistedSnapshotOrder(
                    id: $0.id,
                    symbol: $0.symbol.rawValue,
                    side: $0.side,
                    amountUSD: canonicalString(for: $0.amountUSD),
                    targetPrice: canonicalString(for: $0.targetPrice),
                    status: $0.status,
                    createdAt: $0.createdAt,
                    resolvedAt: $0.resolvedAt
                )
            }
        )

        return try JSONEncoder().encode(persistedSnapshot)
    }

    static func decodeSnapshot(
        id: UUID,
        createdAt: Date,
        payload: Data
    ) throws -> PortfolioSnapshot {
        let persistedSnapshot = try JSONDecoder().decode(
            PersistedPortfolioSnapshot.self,
            from: payload
        )

        let positions = try persistedSnapshot.positions.map {
            try AssetPosition(
                symbol: AssetSymbol($0.symbol),
                amount: decimal(from: $0.amount)
            )
        }
        let portfolio = try Portfolio(positions: positions)
        let constraints = try TradingConstraints(
            tradingStyle: persistedSnapshot.constraints.tradingStyle,
            riskTolerance: persistedSnapshot.constraints.riskTolerance,
            leverageAllowed: persistedSnapshot.constraints.leverageAllowed,
            additionalMonthlyIncomeUSD: decimal(
                from: persistedSnapshot.constraints.additionalMonthlyIncomeUSD
            ),
            minimumStableReserveUSD: decimal(
                from: persistedSnapshot.constraints.minimumStableReserveUSD
            )
        )
        let orders = try persistedSnapshot.orders.map {
            try LimitOrder(
                id: $0.id,
                symbol: AssetSymbol($0.symbol),
                side: $0.side,
                amountUSD: decimal(from: $0.amountUSD),
                targetPrice: decimal(from: $0.targetPrice),
                status: $0.status,
                createdAt: $0.createdAt,
                resolvedAt: $0.resolvedAt
            )
        }

        return PortfolioSnapshot(
            id: id,
            createdAt: createdAt,
            portfolio: portfolio,
            constraints: constraints,
            orders: orders
        )
    }

    static func encodeAnalysis(_ analysis: PortfolioAnalysis) throws -> Data {
        let persisted = PersistedPortfolioAnalysis(
            id: analysis.id,
            generatedAt: analysis.generatedAt,
            snapshotID: analysis.snapshotID,
            analysisMode: analysis.analysisMode,
            riskLevel: analysis.riskLevel,
            portfolioSummary: PersistedPortfolioSummary(
                totalValueUSD: canonicalString(for: analysis.portfolioSummary.totalValueUSD),
                stableValueUSD: canonicalString(for: analysis.portfolioSummary.stableValueUSD),
                investedValueUSD: canonicalString(
                    for: analysis.portfolioSummary.investedValueUSD
                ),
                stableAllocationPercentage: canonicalString(
                    for: analysis.portfolioSummary.stableAllocationPercentage
                ),
                openBuyOrdersUSD: canonicalString(
                    for: analysis.portfolioSummary.openBuyOrdersUSD
                ),
                openSellOrdersUSD: canonicalString(
                    for: analysis.portfolioSummary.openSellOrdersUSD
                ),
                deployableStableUSD: canonicalString(
                    for: analysis.portfolioSummary.deployableStableUSD
                ),
                allocations: analysis.portfolioSummary.allocations.map {
                    PersistedPortfolioAllocation(
                        asset: $0.asset.rawValue,
                        valueUSD: canonicalString(for: $0.valueUSD),
                        allocationPercentage: canonicalString(for: $0.allocationPercentage)
                    )
                }
            ),
            marketSummary: analysis.marketSummary,
            actions: analysis.actions.map {
                PersistedPortfolioAction(
                    id: $0.id,
                    asset: $0.asset?.rawValue,
                    type: $0.type,
                    side: $0.side,
                    price: $0.price.map(canonicalString(for:)),
                    amountUSD: $0.amountUSD.map(canonicalString(for:)),
                    priority: $0.priority,
                    reason: $0.reason
                )
            },
            assetAnalysis: analysis.assetAnalysis.map {
                PersistedAssetAnalysis(
                    asset: $0.asset.rawValue,
                    valueUSD: canonicalString(for: $0.valueUSD),
                    allocationPercentage: canonicalString(for: $0.allocationPercentage),
                    assessment: $0.assessment,
                    recommendation: $0.recommendation
                )
            },
            warnings: analysis.warnings.map {
                PersistedPortfolioWarning(
                    code: $0.code,
                    severity: $0.severity,
                    message: $0.message,
                    asset: $0.asset?.rawValue
                )
            }
        )

        return try JSONEncoder().encode(persisted)
    }

    static func decodeAnalysis(_ data: Data) throws -> PortfolioAnalysis {
        let persisted = try JSONDecoder().decode(PersistedPortfolioAnalysis.self, from: data)
        let totalValueUSD = try decimal(from: persisted.portfolioSummary.totalValueUSD)
        let stableValueUSD = try decimal(from: persisted.portfolioSummary.stableValueUSD)
        let stableAllocationPercentage = try persisted.portfolioSummary
            .stableAllocationPercentage
            .map(decimal(from:))
            ?? (totalValueUSD > 0 ? stableValueUSD * 100 / totalValueUSD : 0)
        return PortfolioAnalysis(
            id: persisted.id,
            generatedAt: persisted.generatedAt,
            snapshotID: persisted.snapshotID,
            analysisMode: persisted.analysisMode ?? .deterministic,
            riskLevel: persisted.riskLevel,
            portfolioSummary: PortfolioSummary(
                totalValueUSD: totalValueUSD,
                stableValueUSD: stableValueUSD,
                investedValueUSD: try decimal(
                    from: persisted.portfolioSummary.investedValueUSD
                ),
                stableAllocationPercentage: stableAllocationPercentage,
                openBuyOrdersUSD: try persisted.portfolioSummary.openBuyOrdersUSD
                    .map(decimal(from:)) ?? 0,
                openSellOrdersUSD: try persisted.portfolioSummary.openSellOrdersUSD
                    .map(decimal(from:)) ?? 0,
                deployableStableUSD: try persisted.portfolioSummary.deployableStableUSD
                    .map(decimal(from:)) ?? 0,
                allocations: try persisted.portfolioSummary.allocations.map {
                    PortfolioAllocation(
                        asset: try AssetSymbol($0.asset),
                        valueUSD: try decimal(from: $0.valueUSD),
                        allocationPercentage: try decimal(from: $0.allocationPercentage)
                    )
                }
            ),
            marketSummary: persisted.marketSummary,
            actions: try persisted.actions.map {
                PortfolioAction(
                    id: $0.id,
                    asset: try $0.asset.map(AssetSymbol.init),
                    type: $0.type,
                    side: $0.side,
                    price: try $0.price.map(decimal(from:)),
                    amountUSD: try $0.amountUSD.map(decimal(from:)),
                    priority: $0.priority,
                    reason: $0.reason
                )
            },
            assetAnalysis: try persisted.assetAnalysis.map {
                AssetAnalysis(
                    asset: try AssetSymbol($0.asset),
                    valueUSD: try decimal(from: $0.valueUSD),
                    allocationPercentage: try decimal(from: $0.allocationPercentage),
                    assessment: $0.assessment,
                    recommendation: $0.recommendation
                )
            },
            warnings: try persisted.warnings.map {
                PortfolioWarning(
                    code: $0.code,
                    severity: $0.severity,
                    message: $0.message,
                    asset: try $0.asset.map(AssetSymbol.init)
                )
            }
        )
    }

    private static func canonicalString(for decimal: Decimal) -> String {
        var decimal = decimal
        return NSDecimalString(&decimal, Locale(identifier: "en_US_POSIX"))
    }

    private static func decimal(from string: String) throws -> Decimal {
        guard let decimal = Decimal(
            string: string,
            locale: Locale(identifier: "en_US_POSIX")
        ), !decimal.isNaN else {
            throw PersistenceMappingError.invalidDecimal(string)
        }

        return decimal
    }
}

private struct PersistedPortfolioSnapshot: Codable {
    let positions: [PersistedSnapshotPosition]
    let constraints: PersistedSnapshotConstraints
    let orders: [PersistedSnapshotOrder]
}

private struct PersistedSnapshotPosition: Codable {
    let symbol: String
    let amount: String
}

private struct PersistedSnapshotConstraints: Codable {
    let tradingStyle: TradingStyle
    let riskTolerance: RiskTolerance
    let leverageAllowed: Bool
    let additionalMonthlyIncomeUSD: String
    let minimumStableReserveUSD: String
}

private struct PersistedSnapshotOrder: Codable {
    let id: UUID
    let symbol: String
    let side: OrderSide
    let amountUSD: String
    let targetPrice: String
    let status: OrderStatus
    let createdAt: Date
    let resolvedAt: Date?
}

private struct PersistedPortfolioAnalysis: Codable {
    let id: UUID
    let generatedAt: Date
    let snapshotID: UUID
    let analysisMode: AnalysisMode?
    let riskLevel: RiskLevel
    let portfolioSummary: PersistedPortfolioSummary
    let marketSummary: MarketSummary
    let actions: [PersistedPortfolioAction]
    let assetAnalysis: [PersistedAssetAnalysis]
    let warnings: [PersistedPortfolioWarning]
}

private struct PersistedPortfolioSummary: Codable {
    let totalValueUSD: String
    let stableValueUSD: String
    let investedValueUSD: String
    let stableAllocationPercentage: String?
    let openBuyOrdersUSD: String?
    let openSellOrdersUSD: String?
    let deployableStableUSD: String?
    let allocations: [PersistedPortfolioAllocation]

    private enum CodingKeys: String, CodingKey {
        case totalValueUSD
        case stableValueUSD
        case legacyCashValueUSD = "cashValueUSD"
        case investedValueUSD
        case stableAllocationPercentage
        case openBuyOrdersUSD
        case openSellOrdersUSD
        case deployableStableUSD
        case allocations
    }

    init(
        totalValueUSD: String,
        stableValueUSD: String,
        investedValueUSD: String,
        stableAllocationPercentage: String,
        openBuyOrdersUSD: String,
        openSellOrdersUSD: String,
        deployableStableUSD: String,
        allocations: [PersistedPortfolioAllocation]
    ) {
        self.totalValueUSD = totalValueUSD
        self.stableValueUSD = stableValueUSD
        self.investedValueUSD = investedValueUSD
        self.stableAllocationPercentage = stableAllocationPercentage
        self.openBuyOrdersUSD = openBuyOrdersUSD
        self.openSellOrdersUSD = openSellOrdersUSD
        self.deployableStableUSD = deployableStableUSD
        self.allocations = allocations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalValueUSD = try container.decode(String.self, forKey: .totalValueUSD)
        stableValueUSD = try container.decodeIfPresent(String.self, forKey: .stableValueUSD)
            ?? container.decode(String.self, forKey: .legacyCashValueUSD)
        investedValueUSD = try container.decode(String.self, forKey: .investedValueUSD)
        stableAllocationPercentage = try container.decodeIfPresent(
            String.self,
            forKey: .stableAllocationPercentage
        )
        openBuyOrdersUSD = try container.decodeIfPresent(
            String.self,
            forKey: .openBuyOrdersUSD
        )
        openSellOrdersUSD = try container.decodeIfPresent(
            String.self,
            forKey: .openSellOrdersUSD
        )
        deployableStableUSD = try container.decodeIfPresent(
            String.self,
            forKey: .deployableStableUSD
        )
        allocations = try container.decode(
            [PersistedPortfolioAllocation].self,
            forKey: .allocations
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalValueUSD, forKey: .totalValueUSD)
        try container.encode(stableValueUSD, forKey: .stableValueUSD)
        try container.encode(investedValueUSD, forKey: .investedValueUSD)
        try container.encodeIfPresent(
            stableAllocationPercentage,
            forKey: .stableAllocationPercentage
        )
        try container.encodeIfPresent(openBuyOrdersUSD, forKey: .openBuyOrdersUSD)
        try container.encodeIfPresent(openSellOrdersUSD, forKey: .openSellOrdersUSD)
        try container.encodeIfPresent(deployableStableUSD, forKey: .deployableStableUSD)
        try container.encode(allocations, forKey: .allocations)
    }
}

private struct PersistedPortfolioAllocation: Codable {
    let asset: String
    let valueUSD: String
    let allocationPercentage: String
}

private struct PersistedPortfolioAction: Codable {
    let id: UUID
    let asset: String?
    let type: PortfolioActionType
    let side: OrderSide?
    let price: String?
    let amountUSD: String?
    let priority: Int
    let reason: String
}

private struct PersistedAssetAnalysis: Codable {
    let asset: String
    let valueUSD: String
    let allocationPercentage: String
    let assessment: String
    let recommendation: String
}

private struct PersistedPortfolioWarning: Codable {
    let code: String
    let severity: WarningSeverity
    let message: String
    let asset: String?
}
