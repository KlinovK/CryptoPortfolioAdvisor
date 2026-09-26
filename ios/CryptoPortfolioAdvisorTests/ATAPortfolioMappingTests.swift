import XCTest

@testable import CryptoPortfolioAdvisor

final class ATAPortfolioMappingTests: XCTestCase {
    private func mapped(_ json: String = ATAFoundationFixtures.portfolio) throws
        -> ATACurrentPortfolio
    {
        try ATAResponseMapper.domain(
            from: JSONDecoder().decode(ATACurrentPortfolioDTO.self, from: Data(json.utf8)))
    }

    func testCompletePortfolioPreservesIdentityOwnershipAndIndependentPositions() throws {
        let value = try mapped()
        XCTAssertEqual(value.revision, 7)
        XCTAssertEqual(value.snapshotID, UUID(uuidString: "00000000-0000-4000-8000-000000000104"))
        XCTAssertEqual(
            value.confirmedAt, try ATATimestampCodec.decode("2026-09-25T12:00:03.000000Z"))
        XCTAssertEqual(value.accounts.count, 2)
        XCTAssertEqual(
            value.accounts[0].id, UUID(uuidString: "00000000-0000-4000-8000-000000000101"))
        XCTAssertEqual(
            value.accounts[1].id, UUID(uuidString: "00000000-0000-4000-8000-000000000102"))
        XCTAssertEqual(value.accounts.map(\.type), [.binance, .externalWallet])
        XCTAssertEqual(value.accounts[0].name, "Trading")
        XCTAssertEqual(value.accounts[0].positions.map(\.symbol), [.btc, .eth, .usdc])
        XCTAssertEqual(value.accounts[1].positions[0].symbol, .btc)
        XCTAssertEqual(
            value.accounts[0].positions[0].amount,
            try ATADecimalCodec.decode("0.12345678901234567890123456789012345678"))
        XCTAssertEqual(value.accounts[1].positions[0].amount, try ATADecimalCodec.decode("0.2"))
        XCTAssertEqual(
            value.aggregatePositions[0].amount,
            try ATADecimalCodec.decode("0.32345678901234567890123456789012345678"))
        XCTAssertNotEqual(value.aggregatePositions, value.accounts[0].positions)
        XCTAssertEqual(value.financialSettings.monthlyExpensesUSD, 250)
        XCTAssertEqual(value.financialSettings.targetExpenseRunwayMonths, 12)
        XCTAssertEqual(value.corePositions[0].symbol, .eth)
        XCTAssertEqual(value.corePositions[0].hardFloor, 2)
        XCTAssertEqual(value.corePositions[0].preferredQuantity, try ATADecimalCodec.decode("2.5"))
        XCTAssertEqual(value.corePositions[0].policyVersion, 1)
        XCTAssertEqual(value.limitOrders.map(\.status), [.open, .filled])
        XCTAssertEqual(value.limitOrders.map(\.side), [.buy, .sell])
        XCTAssertEqual(
            value.limitOrders[0].id, UUID(uuidString: "00000000-0000-4000-8000-000000000103"))
        XCTAssertEqual(value.limitOrders[0].accountID, value.accounts[0].id)
        XCTAssertEqual(value.limitOrders[0].asset, .btc)
        XCTAssertEqual(value.limitOrders[0].targetPrice, 50000)
        XCTAssertEqual(value.limitOrders[0].quantityAsset, try ATADecimalCodec.decode("0.01"))
        XCTAssertNil(value.limitOrders[0].resolvedAt)
        XCTAssertEqual(value.limitOrders[1].resolvedAt, value.confirmedAt)
        XCTAssertEqual(value.limitOrders[1].updatedAt, value.confirmedAt)
    }

    func testAccountResponseUsesIDAndTypeNotRequestFieldNames() throws {
        for json in [
            #"{"id":"00000000-0000-4000-8000-000000000101","name":"Same name","account_type":"manual","positions":[]}"#,
            #"{"account_id":"00000000-0000-4000-8000-000000000101","name":"Same name","type":"manual","positions":[]}"#,
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(ATAAccountDTO.self, from: Data(json.utf8)))
        }
        let json =
            #"{"id":"00000000-0000-4000-8000-000000000101","name":" Same name ","type":"manual","positions":[]}"#
        let value = try ATAResponseMapper.domain(
            from: JSONDecoder().decode(ATAAccountDTO.self, from: Data(json.utf8)))
        XCTAssertEqual(value.name, " Same name ")
        XCTAssertEqual(value.type, .manual)
        XCTAssertTrue(value.positions.isEmpty)
    }

    func testPositionRequiresPositiveAmountInDomainAndMapping() throws {
        for amount in [Decimal.zero, -1, .nan] {
            XCTAssertThrowsError(try ATAPosition(symbol: .btc, amount: amount))
        }
        for amount in ["0", "-0", "-1", "NaN", "0.01junk", "1e-3"] {
            let json = "{\"symbol\":\"BTC\",\"amount\":\"\(amount)\"}"
            XCTAssertThrowsError(
                try ATAResponseMapper.domain(
                    from: JSONDecoder().decode(ATAPositionDTO.self, from: Data(json.utf8))))
        }
    }

    func testFinancialJSONNumbersAreNotCoercedToStrings() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ATAPositionDTO.self, from: Data(#"{"symbol":"BTC","amount":0.01}"#.utf8)))
    }

    func testInvalidUUIDAndNoncanonicalSymbolsFail() {
        for id in ["invalid", "", "00000000-0000-0000-0000-000000000000"] {
            XCTAssertThrowsError(try ATAResponseMapper.identity(id))
        }
        for symbol in ["btc", " BTC", "BTC ", "", "A/B"] {
            XCTAssertThrowsError(try ATAResponseMapper.symbol(symbol))
        }
    }

    func testUnknownPortfolioEnumsNeverDefault() {
        for (known, unknown) in [
            ("binance", "unknown_account"), ("buy", "BUY"), ("open", "unknown_status"),
        ] {
            XCTAssertThrowsError(
                try mapped(
                    ATAFoundationFixtures.portfolio.replacingOccurrences(
                        of: "\"\(known)\"", with: "\"\(unknown)\"")))
        }
    }

    func testRequiredNullableResolvedAtCannotBeOmitted() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(ATAFoundationFixtures.portfolio.utf8))
                as? [String: Any])
        var orders = try XCTUnwrap(object["limit_orders"] as? [[String: Any]])
        orders[0].removeValue(forKey: "resolved_at")
        object["limit_orders"] = orders
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ATACurrentPortfolioDTO.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}
