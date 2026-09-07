import json
from decimal import Decimal
from pathlib import Path
from uuid import uuid4

import httpx
import pytest
from jsonschema import FormatChecker, validate

from app.api.models import AnalyzePortfolioRequestDTO
from app.dependencies import get_analysis_service
from app.domain.errors import (
    IdempotencyConflictError,
    MalformedMarketDataError,
    ProviderRateLimitedError,
    ProviderUnavailableError,
    StaleMarketDataError,
    UnsupportedSymbolError,
)
from app.main import app


def valid_payload() -> dict[str, object]:
    return {
        "snapshot_id": str(uuid4()),
        "created_at": "2026-09-04T09:42:00Z",
        "portfolio": {
            "positions": [
                {"symbol": "BTC", "amount": "0.0198"},
                {"symbol": "LINK", "amount": "8.630000000000001"},
            ]
        },
        "constraints": {
            "trading_style": "active",
            "risk_tolerance": "conservative",
            "leverage_allowed": False,
            "additional_monthly_income_usd": "0",
            "minimum_stable_reserve_usd": "800.000000000000001",
        },
        "orders": [
            {
                "id": "c454346d-e263-4c8e-aac5-b63514d8c3fc",
                "symbol": "BTC",
                "side": "buy",
                "amount_usd": "200.000000000000001",
                "target_price": "76500.125",
                "status": "open",
                "created_at": "2026-09-03T09:42:00Z",
                "resolved_at": None,
            }
        ],
    }


def test_staging_smoke_fixture_is_a_valid_request() -> None:
    fixture_path = Path(__file__).parents[1] / "deployment" / "staging-smoke-portfolio.json"

    request = AnalyzePortfolioRequestDTO.model_validate_json(fixture_path.read_text())

    assert tuple(position.symbol for position in request.portfolio.positions) == (
        "BTC",
        "ETH",
        "SOL",
        "LINK",
        "USDT",
        "USDC",
    )


async def post_analysis(payload: dict[str, object]) -> httpx.Response:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        return await client.post("/v1/portfolio/analyze", json=payload)


@pytest.mark.asyncio
async def test_valid_post_returns_200() -> None:
    response = await post_analysis(valid_payload())

    assert response.status_code == 200
    assert response.json()["risk_level"] == "high"
    assert response.json()["analysis_mode"] == "deterministic"


@pytest.mark.asyncio
async def test_response_validates_against_shared_json_schema() -> None:
    response = await post_analysis(valid_payload())
    schema_path = Path(__file__).parents[2] / "contracts" / "portfolio-analysis.schema.json"
    schema = json.loads(schema_path.read_text())

    validate(response.json(), schema, format_checker=FormatChecker())


@pytest.mark.asyncio
async def test_same_snapshot_returns_same_analysis_id_and_result() -> None:
    payload = valid_payload()
    first = await post_analysis(payload)
    second = await post_analysis(payload)

    assert first.json()["analysis_id"] == second.json()["analysis_id"]
    assert first.json() == second.json()


def test_decimal_strings_are_parsed_losslessly() -> None:
    payload = valid_payload()
    payload["portfolio"]["positions"][0]["amount"] = "0.1234567890123456789012345678"

    request = AnalyzePortfolioRequestDTO.model_validate(payload)

    assert request.portfolio.positions[0].amount == Decimal("0.1234567890123456789012345678")


@pytest.mark.asyncio
async def test_duplicate_portfolio_symbols_are_rejected() -> None:
    payload = valid_payload()
    payload["portfolio"]["positions"].append({"symbol": "BTC", "amount": "1"})

    response = await post_analysis(payload)

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_request"


@pytest.mark.asyncio
async def test_negative_asset_amount_is_rejected() -> None:
    payload = valid_payload()
    payload["portfolio"]["positions"][0]["amount"] = "-0.1"

    response = await post_analysis(payload)

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_zero_order_amount_is_rejected() -> None:
    payload = valid_payload()
    payload["orders"][0]["amount_usd"] = "0"

    response = await post_analysis(payload)

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_negative_target_price_is_rejected() -> None:
    payload = valid_payload()
    payload["orders"][0]["target_price"] = "-1"

    response = await post_analysis(payload)

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_negative_monthly_income_is_rejected() -> None:
    payload = valid_payload()
    payload["constraints"]["additional_monthly_income_usd"] = "-1"

    response = await post_analysis(payload)

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_negative_stable_reserve_is_rejected() -> None:
    payload = valid_payload()
    payload["constraints"]["minimum_stable_reserve_usd"] = "-1"

    response = await post_analysis(payload)

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_arbitrary_link_asset_is_accepted() -> None:
    response = await post_analysis(valid_payload())

    assert response.status_code == 200
    assert [item["asset"] for item in response.json()["asset_analysis"]] == ["BTC", "LINK"]


@pytest.mark.asyncio
async def test_response_labels_static_prices_as_non_live() -> None:
    response = await post_analysis(valid_payload())
    body = response.json()

    assert all(action["price"] is None for action in body["actions"])
    assert body["portfolio_summary"]["total_value_usd"] == "1317.450000000000015"
    assert "Values are not live" in body["market_summary"]["overview"]
    assert "DEVELOPMENT_MARKET_DATA" in [warning["code"] for warning in body["warnings"]]


@pytest.mark.asyncio
async def test_response_includes_correct_snapshot_id() -> None:
    payload = valid_payload()

    response = await post_analysis(payload)

    assert response.json()["snapshot_id"] == payload["snapshot_id"]


@pytest.mark.asyncio
async def test_leverage_setting_is_preserved_in_risk_assessment() -> None:
    payload = valid_payload()
    payload["constraints"]["leverage_allowed"] = True

    response = await post_analysis(payload)
    body = response.json()

    assert body["risk_level"] == "high"
    assert "LEVERAGE_POLICY_VIOLATION" in [warning["code"] for warning in body["warnings"]]


@pytest.mark.asyncio
async def test_missing_static_market_price_is_an_explicit_validation_failure() -> None:
    payload = valid_payload()
    payload["portfolio"]["positions"] = [{"symbol": "JITO", "amount": "1"}]

    response = await post_analysis(payload)

    assert response.status_code == 400
    assert response.json() == {
        "error": {
            "code": "invalid_request",
            "message": "Market price is unavailable for JITO.",
        }
    }


@pytest.mark.asyncio
async def test_zero_value_portfolio_returns_safe_metrics_and_wait_action() -> None:
    payload = valid_payload()
    payload["portfolio"]["positions"] = []
    payload["orders"] = []
    payload["constraints"]["minimum_stable_reserve_usd"] = "0"

    response = await post_analysis(payload)
    body = response.json()

    assert response.status_code == 200
    assert body["portfolio_summary"]["total_value_usd"] == "0"
    assert body["portfolio_summary"]["stable_allocation_pct"] == "0"
    assert body["actions"][0]["type"] == "wait"
    assert body["actions"][0]["amount_usd"] is None


@pytest.mark.asyncio
async def test_malformed_transport_uses_stable_error_envelope() -> None:
    payload = valid_payload()
    payload["portfolio"]["positions"][0]["amount"] = 0.1

    response = await post_analysis(payload)

    assert response.status_code == 422
    assert response.json() == {
        "error": {
            "code": "malformed_request",
            "message": "Request payload is malformed.",
        }
    }


@pytest.mark.asyncio
async def test_unexpected_failure_uses_stable_internal_error_envelope() -> None:
    class FailingService:
        async def analyze(self, _snapshot: object) -> None:
            raise RuntimeError("sensitive implementation detail")

    app.dependency_overrides[get_analysis_service] = lambda: FailingService()
    try:
        transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post("/v1/portfolio/analyze", json=valid_payload())
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 500
    assert response.json() == {
        "error": {
            "code": "internal_error",
            "message": "An internal server error occurred.",
        }
    }
    assert "sensitive" not in response.text
    assert "X-Request-ID" in response.headers


@pytest.mark.parametrize(
    ("error", "status_code", "code"),
    [
        (UnsupportedSymbolError("JITO"), 400, "unsupported_symbol"),
        (ProviderUnavailableError(), 503, "provider_unavailable"),
        (ProviderRateLimitedError(), 503, "provider_rate_limited"),
        (StaleMarketDataError(), 503, "stale_market_data"),
        (MalformedMarketDataError(), 502, "malformed_market_data"),
    ],
)
@pytest.mark.asyncio
async def test_market_data_failures_use_stable_api_envelope(
    error: Exception,
    status_code: int,
    code: str,
) -> None:
    class FailingService:
        async def analyze(self, _snapshot: object) -> None:
            raise error

    app.dependency_overrides[get_analysis_service] = lambda: FailingService()
    try:
        response = await post_analysis(valid_payload())
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == status_code
    assert response.json()["error"]["code"] == code
    assert "CoinGecko" not in response.text


@pytest.mark.asyncio
async def test_idempotency_conflict_uses_explicit_sanitized_409() -> None:
    class ConflictingService:
        async def analyze(self, _snapshot: object) -> None:
            raise IdempotencyConflictError()

    app.dependency_overrides[get_analysis_service] = lambda: ConflictingService()
    try:
        response = await post_analysis(valid_payload())
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 409
    assert response.json()["error"] == {
        "code": "idempotency_conflict",
        "message": "The snapshot ID was already used with different portfolio data.",
    }
