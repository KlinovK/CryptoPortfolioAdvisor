import XCTest

@testable import CryptoPortfolioAdvisor

final class ATAAnalysisMappingTests: XCTestCase {
    private func mapped(_ json: String = ATAFoundationFixtures.detail) throws -> ATAAnalysisDetail {
        try ATAResponseMapper.domain(
            from: JSONDecoder().decode(ATAAnalysisDetailDTO.self, from: Data(json.utf8)))
    }

    func testListContainsOnlyRunMetadataAndPreservesNullability() throws {
        let value = try ATAResponseMapper.domain(
            from: JSONDecoder().decode(
                ATARecentAnalysesDTO.self, from: Data(ATAFoundationFixtures.list.utf8)))
        XCTAssertEqual(value.analyses.count, 2)
        XCTAssertEqual(value.analyses.map(\.status), [.completed, .running])
        XCTAssertEqual(
            value.analyses[0].runID, UUID(uuidString: "00000000-0000-4000-8000-000000000105"))
        XCTAssertEqual(
            value.analyses[0].snapshotID, UUID(uuidString: "00000000-0000-4000-8000-000000000104"))
        XCTAssertNotEqual(value.analyses[0].runID, value.analyses[0].snapshotID)
        XCTAssertNil(value.analyses[1].completedAt)
        XCTAssertNil(value.analyses[1].marketCutoff)
    }

    func testNonCompletedDetailsHaveNoInventedResult() throws {
        for status in ["running", "failed", "cancelled"] {
            let value = try mapped(
                ATAFoundationFixtures.pending.replacingOccurrences(of: "running", with: status))
            XCTAssertNil(value.result)
            XCTAssertNil(value.failureCategory)
            XCTAssertEqual(value.run.status.rawValue, status)
        }
        let failed = try mapped(
            ATAFoundationFixtures.pending.replacingOccurrences(
                of: #""failure_category": null"#, with: #""failure_category": "future_diagnostic""#)
        )
        XCTAssertEqual(failed.failureCategory, "future_diagnostic")
    }

    func testCompletedDetailPreservesHistoricalIdentityFinancialsAndMarket() throws {
        let value = try mapped()
        let result = try XCTUnwrap(value.result)
        XCTAssertEqual(result.runID, value.run.runID)
        XCTAssertEqual(result.snapshotID, value.run.snapshotID)
        XCTAssertEqual(result.generatedAt, value.run.completedAt)
        XCTAssertEqual(result.marketCutoff, value.run.marketCutoff)
        XCTAssertEqual(result.marketRegime, .neutral)
        XCTAssertEqual(result.regimePolicyVersion, 1)
        XCTAssertEqual(result.recommendationPolicyVersion, 1)
        XCTAssertEqual(
            result.financial.totalPortfolioUSD,
            try ATADecimalCodec.decode("31920.035735246913580024691358002469135"))
        XCTAssertEqual(result.financial.currentStablesUSD, 2000)
        XCTAssertEqual(
            result.financial.stableAllocationPercent,
            try ATADecimalCodec.decode("6.265656686813502289436000384889281028"))
        XCTAssertEqual(result.financial.monthlyExpensesUSD, 250)
        XCTAssertEqual(result.financial.targetExpenseRunwayMonths, 12)
        XCTAssertEqual(result.financial.recommendedMinimumStablesUSD, 3000)
        XCTAssertEqual(result.financial.deployableStablesUSD, 0)
        XCTAssertEqual(result.financial.stableReserveDeficitUSD, 1000)
        XCTAssertEqual(result.financial.actualExpenseRunwayMonths, 8)
        XCTAssertEqual(result.financial.openBuyCommitmentsUSD, 500)
        XCTAssertEqual(result.financial.hardExpenseReserveUSD, 3000)
        XCTAssertEqual(result.financial.marketBufferUSD, 0)
        XCTAssertEqual(result.financial.potentialTradingLiquidityUSD, 0)
        XCTAssertEqual(result.financial.strategyDryPowderUSD, 0)
        XCTAssertEqual(result.financial.recommendedDeploymentUSD, 0)
        XCTAssertEqual(result.warnings, ["stable_reserve_deficit", "future_diagnostic"])
        XCTAssertTrue(result.market.isLive)
        XCTAssertEqual(result.market.asOf, result.marketCutoff)
        let asset = try XCTUnwrap(result.market.assets.first)
        XCTAssertEqual(asset.symbol, .btc)
        XCTAssertEqual(asset.priceUSD, 60500)
        XCTAssertEqual(asset.quotedAt, result.generatedAt)
        XCTAssertEqual(asset.latestClosedCandleAt, result.marketCutoff)
        XCTAssertEqual(asset.latestClosedPriceUSD, 60500)
        XCTAssertEqual(asset.completeness, .complete)
        XCTAssertEqual(asset.technicalFeatures.change24hPct, try ATADecimalCodec.decode("-1.5"))
        XCTAssertEqual(asset.technicalFeatures.change7dPct, 2)
        XCTAssertEqual(asset.technicalFeatures.rsi4H, 55)
        XCTAssertEqual(asset.technicalFeatures.ema204H, 60000)
        XCTAssertEqual(asset.technicalFeatures.ema504H, 58000)
        XCTAssertEqual(asset.technicalFeatures.atr4H, 1000)
        XCTAssertEqual(asset.technicalFeatures.support, 59000)
        XCTAssertEqual(asset.technicalFeatures.resistance, 64000)
        XCTAssertEqual(asset.dailyContext.trend, .incomplete)
        XCTAssertNil(asset.dailyContext.ema50)
        XCTAssertNil(asset.dailyContext.resistance)
        XCTAssertEqual(asset.closed1HCandles.count, 1)
        XCTAssertEqual(asset.closed1HCandles[0].open, 60000)
        XCTAssertEqual(asset.closed1HCandles[0].high, 61000)
        XCTAssertEqual(asset.closed1HCandles[0].low, 59000)
        XCTAssertEqual(asset.closed1HCandles[0].close, 60500)
        XCTAssertEqual(asset.closed1HCandles[0].closedAt, result.marketCutoff)
    }

    func testActiveSetupTriggerScoreAndRecommendationTermsArePreserved() throws {
        let result = try XCTUnwrap(mapped().result)
        let active = try XCTUnwrap(result.active)
        let setup = try XCTUnwrap(active.setups.first)
        let trigger = try XCTUnwrap(setup.trigger)
        let recommendation = try XCTUnwrap(result.recommendations.first)
        XCTAssertEqual(active.policyVersion, 3)
        XCTAssertEqual(active.severity, .update)
        XCTAssertEqual(active.rankedSetupIDs, [setup.id])
        XCTAssertEqual(active.recommendedDeploymentUSD, 0)
        XCTAssertEqual(active.strategyDryPowderUSD, 0)
        XCTAssertEqual(setup.id, UUID(uuidString: "00000000-0000-4000-8000-000000000107"))
        XCTAssertEqual(setup.asset, .btc)
        XCTAssertEqual(setup.direction, .buy)
        XCTAssertEqual(setup.setupType, .supportHold)
        XCTAssertEqual(setup.status, .confirmed)
        XCTAssertEqual(setup.limitPrice, 60000)
        XCTAssertEqual(setup.invalidationPrice, 58000)
        XCTAssertEqual(setup.targetPrice, 64000)
        XCTAssertEqual(setup.riskReward, 2)
        XCTAssertEqual(setup.maximumCapitalUSD, 200)
        XCTAssertEqual(setup.score.version, 1)
        XCTAssertEqual(
            setup.score.components,
            [
                ATAScoreComponent(name: "trend", points: 20, maximum: 25),
                ATAScoreComponent(name: "liquidity", points: 15, maximum: 25),
            ])
        XCTAssertEqual(setup.levels[0].price, 60000)
        XCTAssertEqual(setup.levels[0].source, "support")
        XCTAssertEqual(setup.levels[0].priority, 1)
        XCTAssertEqual(trigger.version, 1)
        XCTAssertEqual(trigger.zoneLow, 59000)
        XCTAssertEqual(trigger.zoneHigh, 61000)
        XCTAssertEqual(trigger.atrAtCreation, 1000)
        XCTAssertTrue(trigger.executionValid)
        XCTAssertEqual(trigger.triggerReferencePrice, 60500)
        XCTAssertEqual(trigger.confirmationCandle, result.market.assets[0].closed1HCandles[0])
        XCTAssertEqual(trigger.transitions[0].previousState, .awaitingConfirmation)
        XCTAssertEqual(trigger.transitions[0].currentState, .confirmed)
        XCTAssertEqual(trigger.transitions[0].reason, .supportHold)
        XCTAssertEqual(trigger.transitions[0].timeframe, .oneHour)
        XCTAssertEqual(trigger.transitions[0].referencePrice, 60500)
        XCTAssertEqual(trigger.transitions[0].marketCutoff, result.marketCutoff)
        XCTAssertEqual(active.assetDecisions[0].decision, .hold)
        XCTAssertEqual(active.assetDecisions[0].setupID, setup.id)
        XCTAssertNil(active.assetDecisions[0].coreFloor)
        XCTAssertNil(active.assetDecisions[0].preferredCore)
        XCTAssertEqual(
            recommendation.recommendationID,
            UUID(uuidString: "00000000-0000-4000-8000-000000000108"))
        XCTAssertEqual(recommendation.asset, .btc)
        XCTAssertEqual(recommendation.actionType, .keepLimitOrder)
        XCTAssertEqual(recommendation.existingOrderID, setup.relatedOrderIDs[0])
        XCTAssertEqual(recommendation.setupID, setup.id)
        XCTAssertEqual(recommendation.priority, 1)
        XCTAssertEqual(recommendation.side, .buy)
        XCTAssertEqual(recommendation.targetPrice, 50000)
        XCTAssertEqual(recommendation.quantityAsset, try ATADecimalCodec.decode("0.01"))
        XCTAssertEqual(recommendation.invalidationCondition, "Closed price below support")
        XCTAssertEqual(recommendation.reviewAt, result.marketCutoff)
        XCTAssertNil(recommendation.expiresAt)
    }

    func testOpaqueConfigurationStringsAreNotReinterpreted() throws {
        let result = try XCTUnwrap(mapped().result)
        let config = try XCTUnwrap(result.configuration)
        XCTAssertEqual(
            config.recommendationParameters,
            #"{"opaque":"preserve exactly","decimal":"0.12345678901234567890"}"#)
        XCTAssertEqual(config.activePolicyParameters, "{}")
        XCTAssertNil(config.reservePolicyParameters)
        XCTAssertNil(config.aiFailureCategory)
        XCTAssertEqual(config.wholePlanVersion, 3)
        XCTAssertEqual(config.aiContextVersion, 3)
        XCTAssertEqual(config.aiSchemaVersion, 2)
        XCTAssertEqual(config.aiPromptVersion, 2)
        XCTAssertEqual(result.reasoningModel, "synthetic-model")
        XCTAssertNil(result.aiWarning)
    }

    func testAllReasoningModesHaveExactUppercaseMapping() throws {
        for mode in ATAReasoningMode.allCases {
            XCTAssertEqual(
                try mapped(
                    ATAFoundationFixtures.detail.replacingOccurrences(
                        of: "AI_ASSISTED", with: mode.rawValue)
                ).result?.reasoningMode, mode)
        }
        XCTAssertThrowsError(
            try mapped(
                ATAFoundationFixtures.detail.replacingOccurrences(
                    of: "AI_ASSISTED", with: "ai_assisted")))
    }

    func testUnknownNestedEnumsFailInsteadOfDefaulting() {
        for known in [
            "neutral", "keep_limit_order", "support_hold", "confirmed", "complete", "incomplete",
            "update", "1h", "closed_1h_support_hold_confirmed",
        ] {
            XCTAssertThrowsError(
                try mapped(
                    ATAFoundationFixtures.detail.replacingOccurrences(
                        of: "\"\(known)\"", with: "\"future_value\"")), known)
        }
    }

    func testUnrepresentableNestedDecimalFailsMapping() {
        XCTAssertThrowsError(
            try mapped(
                ATAFoundationFixtures.detail.replacingOccurrences(
                    of: "\"60500\"", with: "\"0.123456789012345678901234567890123456789123456789\"")
            ))
    }

    func testResultIdentityMismatchIsRejected() {
        XCTAssertThrowsError(
            try mapped(
                ATAFoundationFixtures.detail.replacingOccurrences(
                    of: #""run_id": "00000000-0000-4000-8000-000000000105","#,
                    with: #""run_id": "00000000-0000-4000-8000-000000000999","#,
                    range: ATAFoundationFixtures.detail.range(
                        of: #""run_id": "00000000-0000-4000-8000-000000000105","#))))
    }

    func testScoreTupleShapeIsStrict() throws {
        let valid = try JSONDecoder().decode(
            ATAScoreComponentDTO.self, from: Data(#"["trend",20,25]"#.utf8))
        XCTAssertEqual(
            ATAResponseMapper.domain(from: valid),
            ATAScoreComponent(name: "trend", points: 20, maximum: 25))
        for json in [
            #"["trend",20]"#, #"["trend",20,25,99]"#, #"["trend","20",25]"#,
            #"{"name":"trend","points":20,"maximum":25}"#,
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(ATAScoreComponentDTO.self, from: Data(json.utf8)))
        }
    }

    func testOptionalResultSectionsStayAbsent() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(ATAFoundationFixtures.detail.utf8))
                as? [String: Any])
        var result = try XCTUnwrap(object["result"] as? [String: Any])
        for key in ["configuration", "active", "reasoning_model", "ai_warning", "market_cutoff"] {
            result[key] = NSNull()
        }
        object["result"] = result
        let dto = try JSONDecoder().decode(
            ATAAnalysisDetailDTO.self, from: JSONSerialization.data(withJSONObject: object))
        let value = try XCTUnwrap(ATAResponseMapper.domain(from: dto).result)
        XCTAssertNil(value.configuration)
        XCTAssertNil(value.active)
        XCTAssertNil(value.reasoningModel)
        XCTAssertNil(value.aiWarning)
        XCTAssertNil(value.marketCutoff)
    }

    func testAllUnavailableTechnicalIndicatorsRemainNil() throws {
        let data = Data(
            #"{"change_24h_pct":null,"change_7d_pct":null,"rsi_4h":null,"ema20_4h":null,"ema50_4h":null,"atr_4h":null,"support":null,"resistance":null}"#
                .utf8)
        let value = try ATAResponseMapper.domain(
            from: JSONDecoder().decode(ATATechnicalFeaturesDTO.self, from: data))
        XCTAssertEqual(
            value,
            ATATechnicalFeatures(
                change24hPct: nil, change7dPct: nil, rsi4H: nil, ema204H: nil, ema504H: nil,
                atr4H: nil, support: nil, resistance: nil))
    }

    func testRecommendationNullableExecutionFieldsRemainNil() throws {
        let data = Data(
            #"{"recommendation_id":"00000000-0000-4000-8000-000000000108","asset":null,"action_type":"wait","priority":1,"reason":"No action","existing_order_id":null,"side":null,"target_price":null,"quantity_asset":null,"invalidation_condition":null,"review_at":null,"expires_at":null,"setup_id":null}"#
                .utf8)
        let value = try ATAResponseMapper.domain(
            from: JSONDecoder().decode(ATARecommendationDTO.self, from: data))
        XCTAssertEqual(value.actionType, .wait)
        XCTAssertNil(value.asset)
        XCTAssertNil(value.existingOrderID)
        XCTAssertNil(value.side)
        XCTAssertNil(value.targetPrice)
        XCTAssertNil(value.quantityAsset)
        XCTAssertNil(value.invalidationCondition)
        XCTAssertNil(value.reviewAt)
        XCTAssertNil(value.expiresAt)
        XCTAssertNil(value.setupID)
    }

    func testRequiredNullableDetailFieldsCannotBeOmitted() throws {
        for key in ["result", "failure_category"] {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(ATAFoundationFixtures.pending.utf8))
                    as? [String: Any])
            object.removeValue(forKey: key)
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    ATAAnalysisDetailDTO.self, from: JSONSerialization.data(withJSONObject: object)),
                key)
        }
    }
}
