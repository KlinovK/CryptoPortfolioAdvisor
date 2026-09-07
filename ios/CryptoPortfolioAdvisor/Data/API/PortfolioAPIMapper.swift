import Foundation

enum PortfolioAPIMapperError: Error, Equatable, Sendable {
    case invalidDecimal(String)
}

enum PortfolioAPIMapper {
    static func request(from snapshot: PortfolioSnapshot) -> AnalyzePortfolioRequestDTO {
        AnalyzePortfolioRequestDTO(
            snapshotID: snapshot.id,
            createdAt: snapshot.createdAt,
            portfolio: .init(
                positions: snapshot.portfolio.positions.map {
                    .init(
                        symbol: $0.symbol.rawValue,
                        amount: canonicalString(for: $0.amount)
                    )
                }
            ),
            constraints: .init(
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
                .init(
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
    }

    static func domain(from response: PortfolioAnalysisResponseDTO) throws -> PortfolioAnalysis {
        PortfolioAnalysis(
            id: response.analysisID,
            generatedAt: response.generatedAt,
            snapshotID: response.snapshotID,
            analysisMode: response.analysisMode,
            riskLevel: response.riskLevel,
            portfolioSummary: PortfolioSummary(
                totalValueUSD: try decimal(from: response.portfolioSummary.totalValueUSD),
                stableValueUSD: try decimal(from: response.portfolioSummary.stableValueUSD),
                investedValueUSD: try decimal(
                    from: response.portfolioSummary.investedValueUSD
                ),
                stableAllocationPercentage: try decimal(
                    from: response.portfolioSummary.stableAllocationPercentage
                ),
                openBuyOrdersUSD: try decimal(
                    from: response.portfolioSummary.openBuyOrdersUSD
                ),
                openSellOrdersUSD: try decimal(
                    from: response.portfolioSummary.openSellOrdersUSD
                ),
                deployableStableUSD: try decimal(
                    from: response.portfolioSummary.deployableStableUSD
                ),
                allocations: try response.portfolioSummary.allocations.map {
                    PortfolioAllocation(
                        asset: try AssetSymbol($0.asset),
                        valueUSD: try decimal(from: $0.valueUSD),
                        allocationPercentage: try decimal(from: $0.allocationPercentage)
                    )
                }
            ),
            marketSummary: MarketSummary(
                asOf: response.marketSummary.asOf,
                overview: response.marketSummary.overview
            ),
            actions: try response.actions.map {
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
            assetAnalysis: try response.assetAnalysis.map {
                AssetAnalysis(
                    asset: try AssetSymbol($0.asset),
                    valueUSD: try decimal(from: $0.valueUSD),
                    allocationPercentage: try decimal(from: $0.allocationPercentage),
                    assessment: $0.assessment,
                    recommendation: $0.recommendation
                )
            },
            warnings: try response.warnings.map {
                PortfolioWarning(
                    code: $0.code,
                    severity: $0.severity,
                    message: $0.message,
                    asset: try $0.asset.map(AssetSymbol.init)
                )
            }
        )
    }

    static func canonicalString(for decimal: Decimal) -> String {
        var decimal = decimal
        return NSDecimalString(&decimal, Locale(identifier: "en_US_POSIX"))
    }

    static func decimal(from string: String) throws -> Decimal {
        guard let decimal = Decimal(
            string: string,
            locale: Locale(identifier: "en_US_POSIX")
        ), !decimal.isNaN else {
            throw PortfolioAPIMapperError.invalidDecimal(string)
        }
        return decimal
    }
}
