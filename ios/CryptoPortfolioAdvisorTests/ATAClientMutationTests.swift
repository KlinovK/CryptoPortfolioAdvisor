import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATAClientMutationTests: XCTestCase {
    func testEveryMutationUsesExactFrozenRouteBodyAndMappedPortfolio() async throws {
        let id = ATAClientTestSupport.id
        let idPath = ATAClientTestSupport.idPath
        let positions = try ATAClientTestSupport.positions()
        let holdings =
            #"[{"symbol":"BTC","amount":"0.12345678901234567890123456789012345678"},{"symbol":"USDC","amount":"2000"}]"#
        try await check(
            "POST", "/v1/portfolio/accounts", 201,
            "{\"expected_revision\":7,\"name\":\"Trading\",\"account_type\":\"binance\",\"positions\":\(holdings)}"
        ) {
            try await $0.createAccount(
                ATACreateAccountRequestDTO(
                    expectedRevision: 7, name: "Trading", accountType: .binance,
                    positions: positions))
        }
        try await check(
            "PATCH", "/v1/portfolio/accounts/" + idPath, 200,
            #"{"expected_revision":7,"name":"Wallet"}"#
        ) {
            try await $0.renameAccount(
                id, ATARenameAccountRequestDTO(expectedRevision: 7, name: "Wallet"))
        }
        try await check(
            "PUT", "/v1/portfolio/accounts/" + idPath + "/holdings", 200,
            "{\"expected_revision\":7,\"positions\":\(holdings)}"
        ) {
            try await $0.updateAccountHoldings(
                id, ATAReplaceAccountHoldingsRequestDTO(expectedRevision: 7, positions: positions))
        }
        try await check(
            "DELETE", "/v1/portfolio/accounts/" + idPath, 200, #"{"expected_revision":7}"#
        ) {
            try await $0.deleteAccount(id, ATADeleteAccountRequestDTO(expectedRevision: 7))
        }
        try await check(
            "PUT", "/v1/portfolio/financial-settings", 200,
            #"{"expected_revision":7,"monthly_expenses_usd":"250.5","target_expense_runway_months":"12"}"#
        ) {
            try await $0.updateFinancialSettings(
                ATAUpdateFinancialSettingsRequestDTO(
                    expectedRevision: 7, monthlyExpensesUSD: ATADecimalCodec.decode("250.5"),
                    targetExpenseRunwayMonths: 12))
        }
        try await check(
            "PUT", "/v1/portfolio/core-positions/ETH", 200,
            #"{"expected_revision":7,"hard_floor":"2","preferred_quantity":"2.5"}"#
        ) {
            try await $0.updateCorePosition(
                .eth,
                ATAUpdateCorePositionRequestDTO(
                    expectedRevision: 7, hardFloor: 2,
                    preferredQuantity: ATADecimalCodec.decode("2.5")))
        }
        try await check(
            "POST", "/v1/portfolio/orders", 201,
            "{\"expected_revision\":7,\"account_id\":\"\(idPath)\",\"asset\":\"BTC\",\"side\":\"buy\",\"target_price\":\"50000\",\"quantity_asset\":\"0.01\"}"
        ) {
            try await $0.createLimitOrder(
                ATACreateOrderRequestDTO(
                    expectedRevision: 7, accountID: id, asset: .btc, side: .buy, targetPrice: 50000,
                    quantityAsset: ATADecimalCodec.decode("0.01")))
        }
        try await check(
            "POST", "/v1/portfolio/orders/" + idPath + "/cancel", 200, #"{"expected_revision":7}"#
        ) {
            try await $0.cancelLimitOrder(id, ATAOrderLifecycleRequestDTO(expectedRevision: 7))
        }
        try await check(
            "POST", "/v1/portfolio/orders/" + idPath + "/expire", 200, #"{"expected_revision":7}"#
        ) {
            try await $0.expireLimitOrder(id, ATAOrderLifecycleRequestDTO(expectedRevision: 7))
        }
        try await check(
            "POST", "/v1/portfolio/orders/" + idPath + "/confirm-filled", 200,
            "{\"expected_revision\":7,\"settlement_asset\":\"USDC\",\"positions\":\(holdings)}"
        ) {
            try await $0.confirmLimitOrderFilled(
                id,
                ATAConfirmOrderFilledRequestDTO(
                    expectedRevision: 7, settlementAsset: .usdc, positions: positions))
        }
    }

    func testRevisionAndStateConflictsArePreservedWithoutReloadOrReplay() async throws {
        for code in ["revision_conflict", "state_conflict"] {
            let reload = code == "revision_conflict" ? #","reload_required":true"# : ""
            let body = "{\"error\":{\"code\":\"\(code)\",\"message\":\"Safe message\"\(reload)}}"
            let probe = ATAHTTPProbe { ATAClientTestSupport.response($0, status: 409, body: body) }
            let client = try ATAClientTestSupport.client(probe)
            do {
                _ = try await mutate(client)
                XCTFail("Expected conflict")
            } catch let error as ATAClientError {
                guard case .http(let failure) = error else {
                    return XCTFail("Expected semantic conflict")
                }
                XCTAssertEqual(failure.statusCode, 409)
                XCTAssertEqual(failure.error.code, code)
                XCTAssertEqual(
                    failure.error.reloadRequired, code == "revision_conflict" ? true : nil)
            }
            let requests = await probe.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testTransportFailuresAfterHandoffAreUncertainAndNeverRetried() async throws {
        for (code, reason) in [
            (URLError.timedOut, ATAMutationUncertainty.timeout),
            (.networkConnectionLost, .connection), (.cannotFindHost, .connection),
            (.cancelled, .cancelled),
        ] {
            let probe = ATAHTTPProbe { _ in throw URLError(code) }
            let client = try ATAClientTestSupport.client(probe)
            do {
                _ = try await mutate(client)
                XCTFail("Expected uncertainty")
            } catch { XCTAssertEqual(error as? ATAClientError, .uncertainMutationOutcome(reason)) }
            let requests = await probe.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMissingMalformedAndUnexpectedMutationResponsesAreUncertain() async throws {
        for (status, body, reason) in [
            (200, "broken", ATAMutationUncertainty.invalidResponse),
            (204, "", .invalidResponse), (302, "", .redirect),
            (500, "gateway error", .invalidResponse),
        ] {
            let probe = ATAHTTPProbe {
                ATAClientTestSupport.response($0, status: status, body: body)
            }
            let client = try ATAClientTestSupport.client(probe)
            do {
                _ = try await mutate(client)
                XCTFail("Expected uncertainty")
            } catch { XCTAssertEqual(error as? ATAClientError, .uncertainMutationOutcome(reason)) }
            let requests = await probe.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testServerFailurePreservesSemanticsButMayHaveCommitted() async throws {
        let probe = ATAHTTPProbe {
            ATAClientTestSupport.response(
                $0, status: 500,
                body: #"{"error":{"code":"internal_error","message":"Could not construct reply"}}"#)
        }
        let client = try ATAClientTestSupport.client(probe)
        do {
            _ = try await mutate(client)
            XCTFail("Expected uncertainty")
        } catch let error as ATAClientError {
            guard case .uncertainMutationOutcome(.serverFailure, let server) = error else {
                return XCTFail("Expected uncertain server failure")
            }
            XCTAssertEqual(server?.statusCode, 500)
            XCTAssertEqual(server?.error.knownCode, .internalError)
        }
    }

    func testMissingCredentialAndInvalidIdentityAreDefinitelyNotSent() async throws {
        let probe = ATAHTTPProbe()
        var credentials = ATAClientTestSupport.credentials
        credentials.load = { throw CredentialStoreError.tokenAbsent }
        let client = try ATAClientTestSupport.client(probe, credentials: credentials)
        do {
            _ = try await mutate(client)
            XCTFail("Expected missing credential")
        } catch { XCTAssertEqual(error as? ATAClientError, .missingCredential) }
        do {
            _ = try await client.deleteAccount(
                UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                ATADeleteAccountRequestDTO(expectedRevision: 7))
            XCTFail("Expected invalid identity")
        } catch { XCTAssertEqual(error as? ATAClientError, .invalidRequest) }
        let requests = await probe.requests
        XCTAssertTrue(requests.isEmpty)
    }

    private func mutate(_ client: ATAClient) async throws -> ATACurrentPortfolio {
        try await client.renameAccount(
            ATAClientTestSupport.id,
            ATARenameAccountRequestDTO(expectedRevision: 7, name: "Renamed"))
    }

    private func check(
        _ method: String, _ path: String, _ status: Int, _ body: String,
        operation: (ATAClient) async throws -> ATACurrentPortfolio
    ) async throws {
        let probe = ATAHTTPProbe { ATAClientTestSupport.response($0, status: status) }
        let result = try await operation(ATAClientTestSupport.client(probe))
        XCTAssertEqual(
            result,
            try ATAResponseMapper.domain(
                from: JSONDecoder().decode(
                    ATACurrentPortfolioDTO.self, from: Data(ATAFoundationFixtures.portfolio.utf8))))
        let requests = await probe.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, method)
        XCTAssertEqual(request.url?.path, path)
        XCTAssertEqual(request.url?.host, "ata.example.com")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(
            request.value(forHTTPHeaderField: "Authorization") == "Bearer "
                + ATAClientTestSupport.secret)
        XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
        let actualData = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(
            String(decoding: actualData, as: UTF8.self).contains(ATAClientTestSupport.secret))
        XCTAssertFalse(request.url!.absoluteString.contains(ATAClientTestSupport.secret))
        let actual = try JSONSerialization.jsonObject(with: actualData) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? NSDictionary
        XCTAssertEqual(actual, expected)
    }
}
