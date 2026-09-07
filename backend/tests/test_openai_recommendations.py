from types import SimpleNamespace

import httpx
import pytest
from openai import APITimeoutError, AuthenticationError, RateLimitError
from pydantic import ValidationError

from app.config import OpenAIReasoningEffort
from app.infrastructure.openai_recommendations import (
    AIRecommendationPlan,
    OpenAIRecommendationService,
)
from app.observability import bind_request_id, reset_request_id
from app.services.recommendations import (
    OpenAIInvalidResponseError,
    OpenAIRateLimitedError,
    OpenAIRefusalError,
    OpenAIUnavailableError,
)
from tests.test_openai_context import make_context


class FakeResponses:
    def __init__(self, response: object | None = None, error: Exception | None = None) -> None:
        self.response = response
        self.error = error
        self.calls: list[dict[str, object]] = []

    async def parse(self, **kwargs):
        self.calls.append(kwargs)
        if self.error is not None:
            raise self.error
        return self.response


class FakeClient:
    def __init__(self, responses: FakeResponses) -> None:
        self.responses = responses


def valid_plan() -> AIRecommendationPlan:
    return AIRecommendationPlan.model_validate(
        {
            "summary": "Maintain reserve and use only a small spot allocation.",
            "actions": [
                {
                    "asset": "LINK",
                    "action_type": "buy",
                    "side": "buy",
                    "amount_usd": "25.125",
                    "price": None,
                    "priority": 2,
                    "reason": "The amount remains within supplied deployable capital.",
                }
            ],
            "observations": ["BTC allocation is concentrated."],
        }
    )


def completed_response(plan: AIRecommendationPlan | None = None) -> object:
    return SimpleNamespace(
        status="completed",
        output=[],
        output_parsed=plan or valid_plan(),
        usage=SimpleNamespace(input_tokens=100, output_tokens=40, total_tokens=140),
    )


def make_service(responses: FakeResponses) -> OpenAIRecommendationService:
    return OpenAIRecommendationService(
        api_key="test-only",
        model="gpt-5.6-terra",
        reasoning_effort=OpenAIReasoningEffort.LOW,
        timeout_seconds=10,
        client=FakeClient(responses),
    )


@pytest.mark.asyncio
async def test_structured_recommendation_parses_to_decimal_domain_values() -> None:
    responses = FakeResponses(completed_response())

    result = await make_service(responses).recommend(make_context())

    assert result.actions[0].asset == "LINK"
    assert str(result.actions[0].amount_usd) == "25.125"
    assert result.observations == ("BTC allocation is concentrated.",)


@pytest.mark.asyncio
async def test_one_responses_api_call_has_no_tools_or_conversation_state() -> None:
    responses = FakeResponses(completed_response())

    await make_service(responses).recommend(make_context())

    assert len(responses.calls) == 1
    request = responses.calls[0]
    assert request["model"] == "gpt-5.6-terra"
    assert request["text_format"] is AIRecommendationPlan
    assert request["reasoning"] == {"effort": "low"}
    assert request["store"] is False
    assert "tools" not in request
    assert "previous_response_id" not in request
    assert "LINK" not in request["instructions"]
    assert "market_features" in request["input"][0]["content"]


@pytest.mark.asyncio
async def test_backend_request_id_is_forwarded_as_openai_client_request_id() -> None:
    responses = FakeResponses(completed_response())
    token = bind_request_id("ios-request-42")
    try:
        await make_service(responses).recommend(make_context())
    finally:
        reset_request_id(token)

    assert responses.calls[0]["extra_headers"] == {"X-Client-Request-Id": "ios-request-42"}


def test_openai_sdk_automatic_retries_are_disabled_by_default(monkeypatch) -> None:
    captured: dict[str, object] = {}

    def fake_client(**kwargs):
        captured.update(kwargs)
        return FakeClient(FakeResponses())

    monkeypatch.setattr("app.infrastructure.openai_recommendations.AsyncOpenAI", fake_client)

    OpenAIRecommendationService(
        api_key="test-only",
        model="configured-model",
        reasoning_effort=OpenAIReasoningEffort.LOW,
        timeout_seconds=10,
    )

    assert captured["max_retries"] == 0


def test_malformed_decimal_action_is_rejected_by_structured_model() -> None:
    payload = valid_plan().model_dump(mode="json")
    payload["actions"][0]["amount_usd"] = "2e2"

    with pytest.raises(ValidationError):
        AIRecommendationPlan.model_validate(payload)


@pytest.mark.asyncio
async def test_openai_refusal_is_not_treated_as_a_plan() -> None:
    refusal = SimpleNamespace(
        status="completed",
        output=[SimpleNamespace(content=[SimpleNamespace(type="refusal")])],
        output_parsed=valid_plan(),
    )

    with pytest.raises(OpenAIRefusalError):
        await make_service(FakeResponses(refusal)).recommend(make_context())


@pytest.mark.asyncio
async def test_incomplete_response_is_mapped_safely() -> None:
    incomplete = SimpleNamespace(status="incomplete", output=[], output_parsed=None)

    with pytest.raises(OpenAIInvalidResponseError, match="incomplete"):
        await make_service(FakeResponses(incomplete)).recommend(make_context())


@pytest.mark.asyncio
async def test_missing_parsed_output_is_mapped_safely() -> None:
    response = SimpleNamespace(status="completed", output=[], output_parsed=None)

    with pytest.raises(OpenAIInvalidResponseError, match="not usable"):
        await make_service(FakeResponses(response)).recommend(make_context())


@pytest.mark.asyncio
async def test_sdk_failure_is_mapped_without_provider_details() -> None:
    with pytest.raises(OpenAIUnavailableError, match="request failed"):
        await make_service(FakeResponses(error=RuntimeError("secret body"))).recommend(
            make_context()
        )


@pytest.mark.asyncio
async def test_rate_limit_is_mapped_safely() -> None:
    request = httpx.Request("POST", "https://api.openai.com/v1/responses")
    response = httpx.Response(429, request=request)
    error = RateLimitError("rate limited", response=response, body=None)

    with pytest.raises(OpenAIRateLimitedError, match="rate limit"):
        await make_service(FakeResponses(error=error)).recommend(make_context())


@pytest.mark.asyncio
async def test_timeout_is_mapped_safely() -> None:
    request = httpx.Request("POST", "https://api.openai.com/v1/responses")

    with pytest.raises(OpenAIUnavailableError, match="temporarily unavailable"):
        await make_service(FakeResponses(error=APITimeoutError(request=request))).recommend(
            make_context()
        )


@pytest.mark.asyncio
async def test_authentication_failure_is_mapped_without_credentials() -> None:
    request = httpx.Request("POST", "https://api.openai.com/v1/responses")
    response = httpx.Response(401, request=request)
    error = AuthenticationError("invalid test credential", response=response, body=None)

    with pytest.raises(OpenAIUnavailableError, match="request failed") as caught:
        await make_service(FakeResponses(error=error)).recommend(make_context())

    assert "credential" not in str(caught.value)
