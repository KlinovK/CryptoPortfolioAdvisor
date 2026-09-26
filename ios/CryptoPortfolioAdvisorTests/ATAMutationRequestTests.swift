import XCTest

@testable import CryptoPortfolioAdvisor

final class ATAMutationRequestTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func positions() throws -> [ATAPosition] {
        try [
            ATAPosition(
                symbol: .btc,
                amount: ATADecimalCodec.decode("0.12345678901234567890123456789012345678")),
            ATAPosition(symbol: .usdc, amount: 2000),
        ]
    }

    func testCreateAccountShapeUsesAccountTypeAndFullPositions() throws {
        let object = try json(
            ATACreateAccountRequestDTO(
                expectedRevision: 7, name: "Trading", accountType: .binance, positions: positions())
        )
        XCTAssertEqual(
            Set(object.keys), ["expected_revision", "name", "account_type", "positions"])
        XCTAssertEqual(object["expected_revision"] as? Int, 7)
        XCTAssertEqual(object["name"] as? String, "Trading")
        XCTAssertEqual(object["account_type"] as? String, "binance")
        let holdings = try XCTUnwrap(object["positions"] as? [[String: String]])
        XCTAssertEqual(
            holdings,
            [
                ["symbol": "BTC", "amount": "0.12345678901234567890123456789012345678"],
                ["symbol": "USDC", "amount": "2000"],
            ])
    }

    func testRenameAccountShapePreservesNonUniqueLabel() throws {
        let object = try json(ATARenameAccountRequestDTO(expectedRevision: 7, name: " Wallet "))
        XCTAssertEqual(Set(object.keys), ["expected_revision", "name"])
        XCTAssertEqual(object["expected_revision"] as? Int, 7)
        XCTAssertEqual(object["name"] as? String, " Wallet ")
    }

    func testHoldingsReplacementCarriesCompleteArrayIncludingEmpty() throws {
        for positions in [try positions(), []] {
            let object = try json(
                ATAReplaceAccountHoldingsRequestDTO(expectedRevision: 7, positions: positions))
            XCTAssertEqual(Set(object.keys), ["expected_revision", "positions"])
            XCTAssertEqual(object["expected_revision"] as? Int, 7)
            XCTAssertEqual((object["positions"] as? [[String: String]])?.count, positions.count)
        }
    }

    func testDeleteHasRevisionJSONBody() throws {
        XCTAssertEqual(
            try json(ATADeleteAccountRequestDTO(expectedRevision: 7)) as? [String: Int],
            ["expected_revision": 7])
    }

    func testFinancialSettingsShapeUsesDecimalStrings() throws {
        let object = try json(
            ATAUpdateFinancialSettingsRequestDTO(
                expectedRevision: 7, monthlyExpensesUSD: ATADecimalCodec.decode("250.50"),
                targetExpenseRunwayMonths: 12))
        XCTAssertEqual(
            Set(object.keys),
            ["expected_revision", "monthly_expenses_usd", "target_expense_runway_months"])
        XCTAssertEqual(object["expected_revision"] as? Int, 7)
        XCTAssertEqual(object["monthly_expenses_usd"] as? String, "250.5")
        XCTAssertEqual(object["target_expense_runway_months"] as? String, "12")
    }

    func testCorePositionShapeUsesDecimalStrings() throws {
        let object = try json(
            ATAUpdateCorePositionRequestDTO(
                expectedRevision: 7, hardFloor: 2, preferredQuantity: ATADecimalCodec.decode("2.5"))
        )
        XCTAssertEqual(Set(object.keys), ["expected_revision", "hard_floor", "preferred_quantity"])
        XCTAssertEqual(object["expected_revision"] as? Int, 7)
        XCTAssertEqual(object["hard_floor"] as? String, "2")
        XCTAssertEqual(object["preferred_quantity"] as? String, "2.5")
    }

    func testOrderCreateContainsOwnerButNoServerAssignedFields() throws {
        let id = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"))
        let object = try json(
            ATACreateOrderRequestDTO(
                expectedRevision: 7, accountID: id, asset: .btc, side: .buy, targetPrice: 50000,
                quantityAsset: ATADecimalCodec.decode("0.01")))
        XCTAssertEqual(
            Set(object.keys),
            ["expected_revision", "account_id", "asset", "side", "target_price", "quantity_asset"])
        XCTAssertEqual(object["expected_revision"] as? Int, 7)
        XCTAssertEqual(object["account_id"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(object["asset"] as? String, "BTC")
        XCTAssertEqual(object["side"] as? String, "buy")
        XCTAssertEqual(object["target_price"] as? String, "50000")
        XCTAssertEqual(object["quantity_asset"] as? String, "0.01")
    }

    func testCancelAndExpireShareRevisionOnlyBodyNotGenericStatus() throws {
        XCTAssertEqual(
            try json(ATAOrderLifecycleRequestDTO(expectedRevision: 7)) as? [String: Int],
            ["expected_revision": 7])
    }

    func testConfirmFilledContainsSettlementAndCompletePositionsWithoutInventedTerms() throws {
        for settlement in [AssetSymbol.usdt, .usdc] {
            let object = try json(
                ATAConfirmOrderFilledRequestDTO(
                    expectedRevision: 7, settlementAsset: settlement, positions: positions()))
            XCTAssertEqual(
                Set(object.keys), ["expected_revision", "settlement_asset", "positions"])
            XCTAssertEqual(object["expected_revision"] as? Int, 7)
            XCTAssertEqual(object["settlement_asset"] as? String, settlement.rawValue)
            XCTAssertEqual(
                object["positions"] as? [[String: String]],
                [
                    ["symbol": "BTC", "amount": "0.12345678901234567890123456789012345678"],
                    ["symbol": "USDC", "amount": "2000"],
                ])
        }
    }

    func testInvalidRequestValuesFailBeforeEncoding() throws {
        for revision in [0, -1] {
            XCTAssertThrowsError(try ATADeleteAccountRequestDTO(expectedRevision: revision))
            XCTAssertThrowsError(try ATAOrderLifecycleRequestDTO(expectedRevision: revision))
        }
        for name in ["", " \n\t"] {
            XCTAssertThrowsError(try ATARenameAccountRequestDTO(expectedRevision: 1, name: name))
            XCTAssertThrowsError(
                try ATACreateAccountRequestDTO(
                    expectedRevision: 1, name: name, accountType: .manual, positions: []))
        }
        let positions = try positions()
        XCTAssertThrowsError(
            try ATAReplaceAccountHoldingsRequestDTO(
                expectedRevision: 1, positions: [positions[0], positions[0]]))
        XCTAssertThrowsError(
            try ATAConfirmOrderFilledRequestDTO(
                expectedRevision: 1, settlementAsset: .btc, positions: positions))
        XCTAssertThrowsError(
            try ATAUpdateFinancialSettingsRequestDTO(
                expectedRevision: 1, monthlyExpensesUSD: 0, targetExpenseRunwayMonths: 12))
        XCTAssertThrowsError(
            try ATAUpdateCorePositionRequestDTO(
                expectedRevision: 1, hardFloor: 2, preferredQuantity: 1))
        XCTAssertThrowsError(
            try ATACreateOrderRequestDTO(
                expectedRevision: 1,
                accountID: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!, asset: .btc,
                side: .sell, targetPrice: 50000, quantityAsset: -1))
    }
}
