import Foundation

extension ATAResponseMapper {

    static func domain(from dto: ATAAnalysisRunDTO) throws -> ATAAnalysisRun {
        return ATAAnalysisRun(
            runID: try identity(dto.runID),
            snapshotID: try identity(dto.snapshotID),
            startedAt: try ATATimestampCodec.decode(dto.startedAt),
            status: try enumeration(dto.status, as: ATAAnalysisRunStatus.self),
            completedAt: try dto.completedAt.map { try ATATimestampCodec.decode($0) },
            marketCutoff: try dto.marketCutoff.map { try ATATimestampCodec.decode($0) }
        )
    }

    static func domain(from dto: ATARecentAnalysesDTO) throws -> ATARecentAnalyses {
        return ATARecentAnalyses(
            analyses: try dto.analyses.map { try domain(from: $0) }
        )
    }

    static func domain(from dto: ATACandleDTO) throws -> ATACandle {
        return ATACandle(
            closedAt: try ATATimestampCodec.decode(dto.closedAt),
            open: try ATADecimalCodec.decode(dto.open),
            high: try ATADecimalCodec.decode(dto.high),
            low: try ATADecimalCodec.decode(dto.low),
            close: try ATADecimalCodec.decode(dto.close)
        )
    }

    static func domain(from dto: ATATechnicalFeaturesDTO) throws -> ATATechnicalFeatures {
        return ATATechnicalFeatures(
            change24hPct: try dto.change24hPct.map { try ATADecimalCodec.decode($0) },
            change7dPct: try dto.change7dPct.map { try ATADecimalCodec.decode($0) },
            rsi4H: try dto.rsi4H.map { try ATADecimalCodec.decode($0) },
            ema204H: try dto.ema204H.map { try ATADecimalCodec.decode($0) },
            ema504H: try dto.ema504H.map { try ATADecimalCodec.decode($0) },
            atr4H: try dto.atr4H.map { try ATADecimalCodec.decode($0) },
            support: try dto.support.map { try ATADecimalCodec.decode($0) },
            resistance: try dto.resistance.map { try ATADecimalCodec.decode($0) }
        )
    }

    static func domain(from dto: ATADailyContextDTO) throws -> ATADailyContext {
        return ATADailyContext(
            latestClosedAt: try dto.latestClosedAt.map { try ATATimestampCodec.decode($0) },
            closedPriceUSD: try dto.closedPriceUSD.map { try ATADecimalCodec.decode($0) },
            ema20: try dto.ema20.map { try ATADecimalCodec.decode($0) },
            ema50: try dto.ema50.map { try ATADecimalCodec.decode($0) },
            support: try dto.support.map { try ATADecimalCodec.decode($0) },
            resistance: try dto.resistance.map { try ATADecimalCodec.decode($0) },
            trend: try enumeration(dto.trend, as: ATADailyTrend.self)
        )
    }

    static func domain(from dto: ATAMarketAssetDTO) throws -> ATAMarketAsset {
        return ATAMarketAsset(
            symbol: try symbol(dto.symbol),
            priceUSD: try ATADecimalCodec.decode(dto.priceUSD),
            quotedAt: try ATATimestampCodec.decode(dto.quotedAt),
            latestClosedCandleAt: try dto.latestClosedCandleAt.map {
                try ATATimestampCodec.decode($0)
            },
            technicalFeatures: try domain(from: dto.technicalFeatures),
            completeness: try enumeration(dto.completeness, as: ATADataCompleteness.self),
            latestClosedPriceUSD: try dto.latestClosedPriceUSD.map {
                try ATADecimalCodec.decode($0)
            },
            dailyContext: try domain(from: dto.dailyContext),
            closed1HCandles: try dto.closed1HCandles.map { try domain(from: $0) }
        )
    }

    static func domain(from dto: ATAMarketSnapshotDTO) throws -> ATAMarketSnapshot {
        return ATAMarketSnapshot(
            asOf: try ATATimestampCodec.decode(dto.asOf),
            assets: try dto.assets.map { try domain(from: $0) },
            isLive: dto.isLive
        )
    }

    static func domain(from dto: ATAFinancialSummaryDTO) throws -> ATAFinancialSummary {
        return ATAFinancialSummary(
            totalPortfolioUSD: try ATADecimalCodec.decode(dto.totalPortfolioUSD),
            currentStablesUSD: try ATADecimalCodec.decode(dto.currentStablesUSD),
            stableAllocationPercent: try ATADecimalCodec.decode(dto.stableAllocationPercent),
            monthlyExpensesUSD: try ATADecimalCodec.decode(dto.monthlyExpensesUSD),
            targetExpenseRunwayMonths: try ATADecimalCodec.decode(dto.targetExpenseRunwayMonths),
            recommendedMinimumStablesUSD: try ATADecimalCodec.decode(
                dto.recommendedMinimumStablesUSD),
            deployableStablesUSD: try ATADecimalCodec.decode(dto.deployableStablesUSD),
            stableReserveDeficitUSD: try ATADecimalCodec.decode(dto.stableReserveDeficitUSD),
            actualExpenseRunwayMonths: try ATADecimalCodec.decode(dto.actualExpenseRunwayMonths),
            openBuyCommitmentsUSD: try ATADecimalCodec.decode(dto.openBuyCommitmentsUSD),
            hardExpenseReserveUSD: try ATADecimalCodec.decode(dto.hardExpenseReserveUSD),
            marketBufferUSD: try ATADecimalCodec.decode(dto.marketBufferUSD),
            potentialTradingLiquidityUSD: try ATADecimalCodec.decode(
                dto.potentialTradingLiquidityUSD),
            strategyDryPowderUSD: try ATADecimalCodec.decode(dto.strategyDryPowderUSD),
            recommendedDeploymentUSD: try ATADecimalCodec.decode(dto.recommendedDeploymentUSD)
        )
    }

    static func domain(from dto: ATARecommendationDTO) throws -> ATARecommendation {
        return ATARecommendation(
            recommendationID: try identity(dto.recommendationID),
            asset: try dto.asset.map { try symbol($0) },
            actionType: try enumeration(dto.actionType, as: ATAActionType.self),
            priority: dto.priority,
            reason: dto.reason,
            existingOrderID: try dto.existingOrderID.map { try identity($0) },
            side: try dto.side.map { try enumeration($0, as: ATAOrderSide.self) },
            targetPrice: try dto.targetPrice.map { try ATADecimalCodec.decode($0) },
            quantityAsset: try dto.quantityAsset.map { try ATADecimalCodec.decode($0) },
            invalidationCondition: dto.invalidationCondition,
            reviewAt: try dto.reviewAt.map { try ATATimestampCodec.decode($0) },
            expiresAt: try dto.expiresAt.map { try ATATimestampCodec.decode($0) },
            setupID: try dto.setupID.map { try identity($0) }
        )
    }

    static func domain(from dto: ATADecisionConfigurationDTO) throws -> ATADecisionConfiguration {
        return ATADecisionConfiguration(
            marketRegimeVersion: dto.marketRegimeVersion,
            stableReserveVersion: dto.stableReserveVersion,
            wholePlanVersion: dto.wholePlanVersion,
            targetRunwayMonths: try ATADecimalCodec.decode(dto.targetRunwayMonths),
            marketSource: dto.marketSource,
            aiEnabled: dto.aiEnabled,
            modelName: dto.modelName,
            reasoningEffort: dto.reasoningEffort,
            aiContextVersion: dto.aiContextVersion,
            aiSchemaVersion: dto.aiSchemaVersion,
            aiPromptVersion: dto.aiPromptVersion,
            aiFailureCategory: dto.aiFailureCategory,
            recommendationParameters: dto.recommendationParameters,
            activePolicyParameters: dto.activePolicyParameters,
            reservePolicyParameters: dto.reservePolicyParameters
        )
    }

    static func domain(from dto: ATASetupLevelDTO) throws -> ATASetupLevel {
        return ATASetupLevel(
            price: try ATADecimalCodec.decode(dto.price),
            source: dto.source,
            priority: dto.priority
        )
    }

    static func domain(from dto: ATASetupScoreDTO) -> ATASetupScore {
        return ATASetupScore(
            version: dto.version,
            components: dto.components.map { domain(from: $0) }
        )
    }

    static func domain(from dto: ATATriggerTransitionDTO) throws -> ATATriggerTransition {
        return ATATriggerTransition(
            previousState: try enumeration(dto.previousState, as: ATASetupStatus.self),
            currentState: try enumeration(dto.currentState, as: ATASetupStatus.self),
            transitionedAt: try ATATimestampCodec.decode(dto.transitionedAt),
            marketCutoff: try ATATimestampCodec.decode(dto.marketCutoff),
            timeframe: try enumeration(dto.timeframe, as: ATATriggerTimeframe.self),
            reason: try enumeration(dto.reason, as: ATATriggerReason.self),
            referencePrice: try ATADecimalCodec.decode(dto.referencePrice)
        )
    }

    static func domain(from dto: ATATriggerContextDTO) throws -> ATATriggerContext {
        return ATATriggerContext(
            version: dto.version,
            zoneLow: try ATADecimalCodec.decode(dto.zoneLow),
            zoneHigh: try ATADecimalCodec.decode(dto.zoneHigh),
            atrAtCreation: try ATADecimalCodec.decode(dto.atrAtCreation),
            transitions: try dto.transitions.map { try domain(from: $0) },
            touchedAt: try dto.touchedAt.map { try ATATimestampCodec.decode($0) },
            highestObservedPrice: try dto.highestObservedPrice.map {
                try ATADecimalCodec.decode($0)
            },
            lowestObservedPrice: try dto.lowestObservedPrice.map { try ATADecimalCodec.decode($0) },
            triggerReferencePrice: try dto.triggerReferencePrice.map {
                try ATADecimalCodec.decode($0)
            },
            confirmationAt: try dto.confirmationAt.map { try ATATimestampCodec.decode($0) },
            confirmationCandle: try dto.confirmationCandle.map { try domain(from: $0) },
            expiresAt: try dto.expiresAt.map { try ATATimestampCodec.decode($0) },
            lastProcessed1HCandleAt: try dto.lastProcessed1HCandleAt.map {
                try ATATimestampCodec.decode($0)
            },
            executionValid: dto.executionValid
        )
    }

    static func domain(from dto: ATATradeSetupDTO) throws -> ATATradeSetup {
        return ATATradeSetup(
            id: try identity(dto.id),
            asset: try symbol(dto.asset),
            direction: try enumeration(dto.direction, as: ATAOrderSide.self),
            setupType: try enumeration(dto.setupType, as: ATASetupType.self),
            createdAt: try ATATimestampCodec.decode(dto.createdAt),
            originatingCutoff: try ATATimestampCodec.decode(dto.originatingCutoff),
            status: try enumeration(dto.status, as: ATASetupStatus.self),
            limitPrice: try ATADecimalCodec.decode(dto.limitPrice),
            priceSource: dto.priceSource,
            invalidationPrice: try ATADecimalCodec.decode(dto.invalidationPrice),
            invalidationSource: dto.invalidationSource,
            targetPrice: try ATADecimalCodec.decode(dto.targetPrice),
            targetSource: dto.targetSource,
            riskReward: try ATADecimalCodec.decode(dto.riskReward),
            maximumCapitalUSD: try ATADecimalCodec.decode(dto.maximumCapitalUSD),
            score: domain(from: dto.score),
            relatedOrderIDs: try dto.relatedOrderIDs.map { try identity($0) },
            levels: try dto.levels.map { try domain(from: $0) },
            trigger: try dto.trigger.map { try domain(from: $0) }
        )
    }

    static func domain(from dto: ATAAssetDecisionDTO) throws -> ATAAssetDecision {
        return ATAAssetDecision(
            asset: try symbol(dto.asset),
            decision: try enumeration(dto.decision, as: ATAAssetDecisionType.self),
            quantity: try ATADecimalCodec.decode(dto.quantity),
            marketValueUSD: try ATADecimalCodec.decode(dto.marketValueUSD),
            allocationPercent: try ATADecimalCodec.decode(dto.allocationPercent),
            coreFloor: try dto.coreFloor.map { try ATADecimalCodec.decode($0) },
            preferredCore: try dto.preferredCore.map { try ATADecimalCodec.decode($0) },
            tradableQuantity: try ATADecimalCodec.decode(dto.tradableQuantity),
            dailyTrend: try enumeration(dto.dailyTrend, as: ATADailyTrend.self),
            setupID: try dto.setupID.map { try identity($0) }
        )
    }

    static func domain(from dto: ATAActiveAnalysisDTO) throws -> ATAActiveAnalysis {
        return ATAActiveAnalysis(
            policyVersion: dto.policyVersion,
            setups: try dto.setups.map { try domain(from: $0) },
            assetDecisions: try dto.assetDecisions.map { try domain(from: $0) },
            rankedSetupIDs: try dto.rankedSetupIDs.map { try identity($0) },
            recommendedDeploymentUSD: try ATADecimalCodec.decode(dto.recommendedDeploymentUSD),
            strategyDryPowderUSD: try ATADecimalCodec.decode(dto.strategyDryPowderUSD),
            severity: try enumeration(dto.severity, as: ATAAnalysisSeverity.self)
        )
    }

    static func domain(from dto: ATAAnalysisResultDTO) throws -> ATAAnalysisResult {
        return ATAAnalysisResult(
            runID: try identity(dto.runID),
            snapshotID: try identity(dto.snapshotID),
            generatedAt: try ATATimestampCodec.decode(dto.generatedAt),
            marketCutoff: try dto.marketCutoff.map { try ATATimestampCodec.decode($0) },
            market: try domain(from: dto.market),
            marketRegime: try enumeration(dto.marketRegime, as: ATAMarketRegime.self),
            regimePolicyVersion: dto.regimePolicyVersion,
            recommendationPolicyVersion: dto.recommendationPolicyVersion,
            financial: try domain(from: dto.financial),
            warnings: dto.warnings,
            recommendations: try dto.recommendations.map { try domain(from: $0) },
            reasoningMode: try enumeration(dto.reasoningMode, as: ATAReasoningMode.self),
            reasoningModel: dto.reasoningModel,
            aiWarning: dto.aiWarning,
            configuration: try dto.configuration.map { try domain(from: $0) },
            active: try dto.active.map { try domain(from: $0) }
        )
    }

    static func domain(from dto: ATAAnalysisDetailDTO) throws -> ATAAnalysisDetail {
        let result = ATAAnalysisDetail(
            run: try domain(from: dto.run),
            result: try dto.result.map { try domain(from: $0) },
            failureCategory: dto.failureCategory
        )
        if let analysis = result.result {
            guard analysis.runID == result.run.runID,
                analysis.snapshotID == result.run.snapshotID
            else {
                throw ATAWireError.inconsistentIdentity
            }
        }
        return result
    }
}
