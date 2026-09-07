import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

final class PortfolioAPITests: XCTestCase {
    func testDebugConfigurationDefaultsToLocalHTTPBackend() throws {
        let url = try PortfolioAPIConfiguration.baseURL(
            configuredValue: nil,
            environment: .debug
        )

        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:8000")
    }

    func testReleaseConfigurationAcceptsHTTPSNonLocalBackend() throws {
        let url = try PortfolioAPIConfiguration.baseURL(
            configuredValue: "https://api.example.com",
            environment: .release
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.example.com")
    }

    func testReleaseConfigurationRejectsHTTPAndLocalhost() {
        XCTAssertThrowsError(
            try PortfolioAPIConfiguration.baseURL(
                configuredValue: "http://api.example.com",
                environment: .release
            )
        ) { error in
            XCTAssertEqual(
                error as? PortfolioAPIConfigurationError,
                .insecureReleaseURL
            )
        }
        XCTAssertThrowsError(
            try PortfolioAPIConfiguration.baseURL(
                configuredValue: "https://127.0.0.1:8000",
                environment: .release
            )
        ) { error in
            XCTAssertEqual(
                error as? PortfolioAPIConfigurationError,
                .localReleaseURL
            )
        }
    }

    func testRequestMappingUsesSnakeCaseAndLosslessDecimalStrings() throws {
        let dto = PortfolioAPIMapper.request(from: try Phase6TestFixtures.snapshot())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let portfolio = try XCTUnwrap(json["portfolio"] as? [String: Any])
        let positions = try XCTUnwrap(portfolio["positions"] as? [[String: Any]])
        let constraints = try XCTUnwrap(json["constraints"] as? [String: Any])
        let orders = try XCTUnwrap(json["orders"] as? [[String: Any]])

        XCTAssertEqual(json["snapshot_id"] as? String, Phase6TestFixtures.snapshotID.uuidString)
        XCTAssertEqual(positions[0]["symbol"] as? String, "LINK")
        XCTAssertEqual(
            positions[0]["amount"] as? String,
            "0.1234567890123456789012345678"
        )
        XCTAssertEqual(
            constraints["minimum_stable_reserve_usd"] as? String,
            "1000.000000000000001"
        )
        XCTAssertEqual(orders[0]["amount_usd"] as? String, "1234.567890123456789")
        XCTAssertEqual(orders[0]["target_price"] as? String, "15.123456789012345")
    }

    func testRepresentativeResponseMapsToDomainLosslessly() throws {
        let data = Data(successJSON.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8000/v1/portfolio/analyze")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let analysis = try PortfolioAPIResponseDecoder.decode(data: data, response: response)

        XCTAssertEqual(analysis.snapshotID, Phase6TestFixtures.snapshotID)
        XCTAssertEqual(analysis.analysisMode, .aiAssisted)
        XCTAssertEqual(
            analysis.portfolioSummary.stableValueUSD,
            Phase6TestFixtures.decimal("400.000000000000001")
        )
        XCTAssertEqual(
            analysis.portfolioSummary.deployableStableUSD,
            Phase6TestFixtures.decimal("149.999999999999999")
        )
        XCTAssertEqual(analysis.actions[0].asset?.rawValue, "LINK")
        XCTAssertEqual(
            analysis.actions[0].price,
            Phase6TestFixtures.decimal("15.123456789012345")
        )
        XCTAssertEqual(
            analysis.actions[0].amountUSD,
            Phase6TestFixtures.decimal("1234.567890123456789")
        )
    }

    func testPhase7PortfolioMetricsMapLosslessly() throws {
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8000/v1/portfolio/analyze")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let analysis = try PortfolioAPIResponseDecoder.decode(
            data: Data(successJSON.utf8),
            response: response
        )

        XCTAssertEqual(
            analysis.portfolioSummary.stableAllocationPercentage,
            Phase6TestFixtures.decimal("32.400000000000001")
        )
        XCTAssertEqual(
            analysis.portfolioSummary.openBuyOrdersUSD,
            Phase6TestFixtures.decimal("200.000000000000001")
        )
        XCTAssertEqual(
            analysis.portfolioSummary.openSellOrdersUSD,
            Phase6TestFixtures.decimal("50.000000000000001")
        )
        XCTAssertEqual(
            analysis.portfolioSummary.deployableStableUSD,
            Phase6TestFixtures.decimal("149.999999999999999")
        )
    }

    func testAllAnalysisModesDecodeFromPublicContract() throws {
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8000/v1/portfolio/analyze")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let cases: [(String, AnalysisMode)] = [
            ("deterministic", .deterministic),
            ("ai_assisted", .aiAssisted),
            ("ai_fallback", .aiFallback)
        ]

        for (rawValue, expected) in cases {
            let json = successJSON.replacingOccurrences(
                of: #""analysis_mode": "ai_assisted""#,
                with: #""analysis_mode": "\#(rawValue)""#
            )
            let analysis = try PortfolioAPIResponseDecoder.decode(
                data: Data(json.utf8),
                response: response
            )
            XCTAssertEqual(analysis.analysisMode, expected)
        }
    }

    func testBackendErrorEnvelopeMapsToTypedClientError() throws {
        let data = Data(#"{"error":{"code":"invalid_request","message":"Duplicate symbol."}}"#.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8000/v1/portfolio/analyze")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        XCTAssertThrowsError(
            try PortfolioAPIResponseDecoder.decode(data: data, response: response)
        ) { error in
            XCTAssertEqual(
                error as? PortfolioAPIClientError,
                .server(
                    statusCode: 400,
                    code: "invalid_request",
                    message: "Duplicate symbol."
                )
            )
        }
    }

    func testInvalidFinancialStringIsRejectedDuringDomainMapping() throws {
        let data = Data(successJSON.replacingOccurrences(of: #""15.123456789012345""#, with: #""NaN""#).utf8)
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8000/v1/portfolio/analyze")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        XCTAssertThrowsError(
            try PortfolioAPIResponseDecoder.decode(data: data, response: response)
        ) { error in
            XCTAssertEqual(error as? PortfolioAPIMapperError, .invalidDecimal("NaN"))
        }
    }

    private var successJSON: String {
        """
        {
          "analysis_id": "20000000-0000-0000-0000-000000000002",
          "generated_at": "2026-09-04T09:42:00Z",
          "snapshot_id": "10000000-0000-0000-0000-000000000001",
          "analysis_mode": "ai_assisted",
          "risk_level": "moderate",
          "portfolio_summary": {
            "total_value_usd": "1234.567890123456789",
            "stable_value_usd": "400.000000000000001",
            "invested_value_usd": "834.567890123456788",
            "stable_allocation_pct": "32.400000000000001",
            "open_buy_orders_usd": "200.000000000000001",
            "open_sell_orders_usd": "50.000000000000001",
            "deployable_stable_usd": "149.999999999999999",
            "allocations": [
              {"asset": "LINK", "value_usd": "1234.567890123456789", "allocation_pct": "100"}
            ]
          },
          "market_summary": {
            "as_of": "2026-09-04T09:42:00Z",
            "overview": "Deterministic analysis using static development data; values are not live."
          },
          "actions": [
            {
              "id": "30000000-0000-0000-0000-000000000003",
              "asset": "LINK",
              "type": "keep_limit_order",
              "side": "buy",
              "price": "15.123456789012345",
              "amount_usd": "1234.567890123456789",
              "priority": 1,
              "reason": "Deterministic fixture action."
            }
          ],
          "asset_analysis": [
            {
              "asset": "LINK",
              "value_usd": "1234.567890123456789",
              "allocation_pct": "100",
              "assessment": "Quantity received.",
              "recommendation": "No AI recommendation."
            }
          ],
          "warnings": [
            {"code": "DEVELOPMENT_MARKET_DATA", "severity": "info", "message": "Static prices only.", "asset": null}
          ]
        }
        """
    }
}
