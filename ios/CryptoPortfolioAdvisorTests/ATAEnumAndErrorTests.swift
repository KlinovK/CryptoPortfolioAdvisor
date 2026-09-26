import XCTest

@testable import CryptoPortfolioAdvisor

final class ATAEnumAndErrorTests: XCTestCase {
    private func check<T: RawRepresentable & CaseIterable & Equatable>(
        _ type: T.Type, values: [String], file: StaticString = #filePath, line: UInt = #line
    ) throws where T.RawValue == String {
        XCTAssertEqual(Set(T.allCases.map(\.rawValue)), Set(values), file: file, line: line)
        for text in values {
            XCTAssertEqual(
                try ATAResponseMapper.enumeration(text, as: type).rawValue, text, file: file,
                line: line)
        }
        for unknown in ["", "future_unknown_value", " " + values[0]] {
            XCTAssertThrowsError(
                try ATAResponseMapper.enumeration(unknown, as: type), file: file, line: line
            ) {
                XCTAssertEqual($0 as? ATAWireError, .unknownEnum, file: file, line: line)
            }
        }
    }

    func testEveryFrozenEnumFamilyMapsExactlyAndRejectsUnknowns() throws {
        try check(
            ATAAccountType.self, values: ["binance", "external_wallet", "other_exchange", "manual"])
        try check(ATAOrderSide.self, values: ["buy", "sell"])
        try check(ATAOrderStatus.self, values: ["open", "filled", "cancelled", "expired"])
        try check(
            ATAAnalysisRunStatus.self, values: ["running", "completed", "failed", "cancelled"])
        try check(ATADailyTrend.self, values: ["bullish", "bearish", "mixed", "incomplete"])
        try check(
            ATADataCompleteness.self, values: ["unavailable", "price_only", "partial", "complete"])
        try check(
            ATAActionType.self,
            values: [
                "buy", "sell", "hold", "wait", "place_limit_order", "keep_limit_order",
                "cancel_limit_order", "replace_limit_order", "rebalance", "rebalance_informational",
            ])
        try check(
            ATASetupStatus.self,
            values: [
                "candidate", "approaching_zone", "zone_touched", "awaiting_confirmation",
                "confirmed", "active", "filled_or_confirmed_manually", "invalidated", "expired",
                "completed", "cancelled",
            ])
        try check(ATATriggerTimeframe.self, values: ["1h", "4h", "manual"])
        try check(
            ATATriggerReason.self,
            values: [
                "approached_deterministic_zone", "closed_1h_range_touched_zone",
                "awaiting_subsequent_closed_1h_confirmation",
                "closed_1h_resistance_rejection_confirmed", "closed_1h_support_hold_confirmed",
                "closed_4h_breakout_invalidated_rejection",
                "closed_4h_breakdown_invalidated_support", "confirmation_window_expired",
                "execution_window_expired", "execution_price_moved_too_far_from_trigger",
                "order_fill_confirmed_manually", "order_cancellation_confirmed_manually",
            ])
        try check(
            ATASetupType.self,
            values: ["pullback_buy", "profit_taking_sell", "support_hold", "resistance_rejection"])
        try check(
            ATAAssetDecisionType.self,
            values: ["add", "hold", "wait", "partial_sell", "sell", "rebalance_informational"])
        try check(ATAAnalysisSeverity.self, values: ["quiet", "update", "action"])
        try check(
            ATAMarketRegime.self,
            values: ["risk_on", "constructive", "neutral", "elevated_risk", "risk_off"])
        try check(ATAReasoningMode.self, values: ["DETERMINISTIC", "AI_ASSISTED", "AI_FALLBACK"])
    }

    func testEveryKnownErrorCodeHasItsOwnMeaning() throws {
        for code in ATAServiceError.KnownCode.allCases {
            let data = Data(
                "{\"error\":{\"code\":\"\(code.rawValue)\",\"message\":\"Safe explanation\"}}".utf8)
            let value = ATAResponseMapper.domain(
                from: try JSONDecoder().decode(ATAErrorEnvelopeDTO.self, from: data))
            XCTAssertEqual(value.knownCode, code)
            XCTAssertEqual(value.code, code.rawValue)
            XCTAssertEqual(value.message, "Safe explanation")
            XCTAssertNil(value.reloadRequired)
        }
    }

    func testUnknownErrorCodeIsPreservedWithoutAssigningKnownMeaning() throws {
        let data = Data(
            #"{"error":{"code":"future_server_code","message":"Compatibility error"}}"#.utf8)
        let value = ATAResponseMapper.domain(
            from: try JSONDecoder().decode(ATAErrorEnvelopeDTO.self, from: data))
        XCTAssertNil(value.knownCode)
        XCTAssertEqual(value.code, "future_server_code")
        XCTAssertEqual(value.message, "Compatibility error")
    }

    func testReloadRequiredIsAbsentOrLiteralTrue() throws {
        let data = Data(
            #"{"error":{"code":"revision_conflict","message":"Reload","reload_required":true}}"#
                .utf8)
        XCTAssertEqual(
            ATAResponseMapper.domain(
                from: try JSONDecoder().decode(ATAErrorEnvelopeDTO.self, from: data)
            ).reloadRequired, true)
        for invalid in ["false", "null", "1", "\"true\""] {
            let json =
                "{\"error\":{\"code\":\"revision_conflict\",\"message\":\"Reload\",\"reload_required\":\(invalid)}}"
            XCTAssertThrowsError(
                try JSONDecoder().decode(ATAErrorEnvelopeDTO.self, from: Data(json.utf8)))
        }
    }
}
