import re
from decimal import Decimal, InvalidOperation
from time import perf_counter

from openai import (
    APIConnectionError,
    APIStatusError,
    APITimeoutError,
    AsyncOpenAI,
    AuthenticationError,
    OpenAIError,
    RateLimitError,
)
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from app.config import OpenAIReasoningEffort
from app.domain.models import (
    AnalysisContext,
    OrderSide,
    PortfolioActionType,
    RecommendationAction,
    RecommendationPlan,
)
from app.observability import current_request_id, get_logger, log_event
from app.services.openai_context import AnalysisContextSerializer
from app.services.recommendations import (
    OpenAIInvalidResponseError,
    OpenAIRateLimitedError,
    OpenAIRefusalError,
    OpenAIUnavailableError,
    RecommendationReasoningError,
)

logger = get_logger("openai")

_CANONICAL_DECIMAL = re.compile(r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$")

OPENAI_INSTRUCTIONS = """You are a portfolio recommendation reasoning component.
Use only the supplied structured context. This product is an advisor and never executes trades.
Do not invent prices, balances, indicators, orders, or market facts. Propose conservative,
spot-only actions compatible with the supplied constraints. Respect stable reserve and capital
already committed to open orders. Do not assume leverage unless explicitly allowed. Do not
perform deterministic portfolio arithmetic; those values are supplied. Return only the required
structured recommendation with concise user-visible reasons. Include at least one action, using
HOLD or WAIT when no trade action is appropriate."""


class StructuredOutputModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class AIProposedAction(StructuredOutputModel):
    asset: str | None = Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$")
    action_type: PortfolioActionType
    side: OrderSide | None
    amount_usd: str | None
    price: str | None
    priority: int = Field(ge=1, le=5)
    reason: str = Field(min_length=1, max_length=300)

    @field_validator("amount_usd", "price")
    @classmethod
    def validate_decimal_string(cls, value: str | None) -> str | None:
        if value is not None and not _CANONICAL_DECIMAL.fullmatch(value):
            raise ValueError("Financial values must be canonical decimal strings.")
        return value


class AIRecommendationPlan(StructuredOutputModel):
    summary: str = Field(min_length=1, max_length=500)
    actions: list[AIProposedAction] = Field(min_length=1, max_length=12)
    observations: list[str] = Field(max_length=12)

    @field_validator("observations")
    @classmethod
    def validate_observations(cls, values: list[str]) -> list[str]:
        if any(not value.strip() or len(value) > 300 for value in values):
            raise ValueError("Observations must be concise non-empty strings.")
        return values


class OpenAIRecommendationService:
    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        reasoning_effort: OpenAIReasoningEffort,
        timeout_seconds: float,
        max_retries: int = 0,
        serializer: AnalysisContextSerializer | None = None,
        client: AsyncOpenAI | None = None,
    ) -> None:
        self._model = model
        self._reasoning_effort = reasoning_effort
        self._serializer = serializer or AnalysisContextSerializer()
        self._client = client or AsyncOpenAI(
            api_key=api_key,
            timeout=timeout_seconds,
            max_retries=max_retries,
        )

    async def recommend(self, context: AnalysisContext) -> RecommendationPlan:
        started_at = perf_counter()
        try:
            request_arguments = {
                "model": self._model,
                "instructions": OPENAI_INSTRUCTIONS,
                "input": [
                    {
                        "role": "user",
                        "content": self._serializer.serialize(context),
                    }
                ],
                "text_format": AIRecommendationPlan,
                "reasoning": {"effort": self._reasoning_effort.value},
                "max_output_tokens": 1_200,
                "store": False,
            }
            request_id = current_request_id()
            if request_id != "-":
                request_arguments["extra_headers"] = {"X-Client-Request-Id": request_id}

            response = await self._client.responses.parse(
                **request_arguments,
            )
            if _contains_refusal(response):
                raise OpenAIRefusalError("The model refused the recommendation request.")

            status = getattr(response, "status", None)
            status_value = getattr(status, "value", status)
            if status_value != "completed":
                raise OpenAIInvalidResponseError("The model response was incomplete.")

            parsed = getattr(response, "output_parsed", None)
            if not isinstance(parsed, AIRecommendationPlan):
                raise OpenAIInvalidResponseError("The model response was not usable.")

            plan = _to_domain(parsed)
            _log_result(
                model=self._model,
                latency_ms=(perf_counter() - started_at) * 1_000,
                category="success",
                proposed_actions=len(plan.actions),
                usage=getattr(response, "usage", None),
                openai_request_id=getattr(response, "_request_id", None),
            )
            return plan
        except RecommendationReasoningError as error:
            _log_result(
                model=self._model,
                latency_ms=(perf_counter() - started_at) * 1_000,
                category=error.category,
            )
            raise
        except RateLimitError as error:
            mapped = OpenAIRateLimitedError("OpenAI rate limit reached.")
            _log_mapped_failure(self._model, started_at, mapped)
            raise mapped from error
        except (APITimeoutError, APIConnectionError) as error:
            mapped = OpenAIUnavailableError("OpenAI is temporarily unavailable.")
            _log_mapped_failure(self._model, started_at, mapped)
            raise mapped from error
        except (AuthenticationError, APIStatusError, OpenAIError) as error:
            mapped = OpenAIUnavailableError("OpenAI request failed.")
            _log_mapped_failure(self._model, started_at, mapped)
            raise mapped from error
        except (ValidationError, InvalidOperation, ValueError, TypeError) as error:
            mapped = OpenAIInvalidResponseError("OpenAI returned an invalid response.")
            _log_mapped_failure(self._model, started_at, mapped)
            raise mapped from error
        except Exception as error:
            mapped = OpenAIUnavailableError("OpenAI request failed.")
            _log_mapped_failure(self._model, started_at, mapped)
            raise mapped from error


def _to_domain(plan: AIRecommendationPlan) -> RecommendationPlan:
    actions = tuple(
        RecommendationAction(
            asset=action.asset.upper() if action.asset is not None else None,
            type=action.action_type,
            side=action.side,
            amount_usd=_parse_decimal(action.amount_usd),
            price=_parse_decimal(action.price),
            priority=action.priority,
            reason=action.reason,
        )
        for action in plan.actions
    )
    return RecommendationPlan(
        summary=plan.summary,
        actions=actions,
        observations=tuple(plan.observations),
    )


def _parse_decimal(value: str | None) -> Decimal | None:
    if value is None:
        return None
    if not _CANONICAL_DECIMAL.fullmatch(value):
        raise OpenAIInvalidResponseError("OpenAI returned a malformed financial value.")
    try:
        parsed = Decimal(value)
    except InvalidOperation as error:
        raise OpenAIInvalidResponseError("OpenAI returned a malformed financial value.") from error
    if not parsed.is_finite():
        raise OpenAIInvalidResponseError("OpenAI returned a non-finite financial value.")
    return parsed


def _contains_refusal(response: object) -> bool:
    for output in getattr(response, "output", ()) or ():
        for content in getattr(output, "content", ()) or ():
            if getattr(content, "type", None) == "refusal":
                return True
    return False


def _log_mapped_failure(
    model: str,
    started_at: float,
    error: RecommendationReasoningError,
) -> None:
    _log_result(
        model=model,
        latency_ms=(perf_counter() - started_at) * 1_000,
        category=error.category,
    )


def _log_result(
    *,
    model: str,
    latency_ms: float,
    category: str,
    proposed_actions: int = 0,
    usage: object | None = None,
    openai_request_id: str | None = None,
) -> None:
    log_event(
        logger,
        "openai_recommendation",
        latency_ms=round(latency_ms, 1),
        openai_outcome=category,
        openai_model=model,
        openai_request_id=openai_request_id,
        input_tokens=getattr(usage, "input_tokens", None),
        output_tokens=getattr(usage, "output_tokens", None),
        total_tokens=getattr(usage, "total_tokens", None),
        proposed_actions=proposed_actions,
    )
