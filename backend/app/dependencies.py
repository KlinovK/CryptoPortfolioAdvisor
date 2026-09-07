from dataclasses import dataclass
from datetime import timedelta

from fastapi import Request

from app.config import (
    AppSettings,
    CoinGeckoAPITier,
    IdempotencyMode,
    MarketDataMode,
    MarketDataSettings,
    OpenAISettings,
)
from app.infrastructure.database import Database
from app.infrastructure.live_market_data import (
    COINGECKO_DEMO_API_KEY_HEADER,
    COINGECKO_DEMO_BASE_URL,
    COINGECKO_PRO_API_KEY_HEADER,
    COINGECKO_PRO_BASE_URL,
    CoinGeckoMarketDataProvider,
)
from app.infrastructure.openai_recommendations import OpenAIRecommendationService
from app.infrastructure.sqlalchemy_idempotency import SQLAlchemyAnalysisIdempotencyStore
from app.infrastructure.static_market_data import StaticMarketDataProvider
from app.services.analysis import (
    AnalysisService,
    BudgetedAnalysisService,
    DeterministicPortfolioAnalysisService,
)
from app.services.analysis_context import AnalysisContextBuilder
from app.services.idempotency import (
    AnalysisIdempotencyStore,
    IdempotentAnalysisService,
    InProcessAnalysisIdempotencyStore,
)
from app.services.market_data import MarketDataPolicy, MarketDataProvider
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.recommendations import RecommendationReasoner
from app.services.risk_engine import RiskEngine, RiskPolicyConfig
from app.services.technical_features import TechnicalFeatureCalculator


@dataclass(slots=True)
class ApplicationRuntime:
    settings: AppSettings
    analysis_service: AnalysisService
    idempotency_store: AnalysisIdempotencyStore
    database: Database | None = None

    async def is_ready(self) -> bool:
        return await self.idempotency_store.is_ready()

    async def close(self) -> None:
        if self.database is not None:
            await self.database.dispose()


def build_market_data_provider(settings: MarketDataSettings) -> MarketDataProvider:
    if settings.mode is MarketDataMode.STATIC:
        return StaticMarketDataProvider.development()
    if settings.coingecko_api_tier is CoinGeckoAPITier.PRO:
        base_url = COINGECKO_PRO_BASE_URL
        api_key_header = COINGECKO_PRO_API_KEY_HEADER
    else:
        base_url = COINGECKO_DEMO_BASE_URL
        api_key_header = COINGECKO_DEMO_API_KEY_HEADER
    return CoinGeckoMarketDataProvider(
        api_key=settings.coingecko_api_key or "",
        api_key_header=api_key_header,
        base_url=base_url,
        feature_calculator=TechnicalFeatureCalculator(),
        policy=MarketDataPolicy(
            max_quote_age=timedelta(seconds=settings.max_quote_age_seconds),
            max_closed_candle_lag=timedelta(
                seconds=settings.max_closed_candle_lag_seconds,
            ),
        ),
        request_timeout_seconds=settings.request_timeout_seconds,
        max_retries=settings.max_retries,
    )


def build_recommendation_reasoner(
    settings: OpenAISettings,
) -> RecommendationReasoner | None:
    if not settings.enabled:
        return None
    return OpenAIRecommendationService(
        api_key=settings.api_key or "",
        model=settings.model,
        reasoning_effort=settings.reasoning_effort,
        timeout_seconds=settings.timeout_seconds,
        max_retries=settings.max_retries,
    )


def build_runtime(settings: AppSettings) -> ApplicationRuntime:
    market_data_provider = build_market_data_provider(settings.market_data)
    recommendation_reasoner = build_recommendation_reasoner(settings.openai)
    core_analysis_service = DeterministicPortfolioAnalysisService(
        market_data_provider=market_data_provider,
        portfolio_calculator=PortfolioCalculator(),
        risk_engine=RiskEngine(RiskPolicyConfig()),
        analysis_context_builder=AnalysisContextBuilder(),
        recommendation_reasoner=recommendation_reasoner,
    )
    operation = BudgetedAnalysisService(
        core_analysis_service,
        settings.analysis_timeout_seconds,
    )

    database = None
    if settings.database.idempotency_mode is IdempotencyMode.DATABASE:
        database = Database(settings.database.url or "")
        store: AnalysisIdempotencyStore = SQLAlchemyAnalysisIdempotencyStore(
            database,
            retention_days=settings.database.retention_days,
            lease_seconds=settings.analysis_timeout_seconds + 5,
            wait_timeout_seconds=settings.analysis_timeout_seconds,
        )
    else:
        store = InProcessAnalysisIdempotencyStore()

    idempotent = IdempotentAnalysisService(operation, store)
    analysis_service = BudgetedAnalysisService(
        idempotent,
        settings.analysis_timeout_seconds,
    )
    return ApplicationRuntime(
        settings=settings,
        analysis_service=analysis_service,
        idempotency_store=store,
        database=database,
    )


def get_runtime(request: Request) -> ApplicationRuntime:
    return request.app.state.runtime


def get_analysis_service(request: Request) -> AnalysisService:
    return get_runtime(request).analysis_service
