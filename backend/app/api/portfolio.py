from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.mappers import analysis_to_response, request_to_domain
from app.api.models import AnalyzePortfolioRequestDTO, PortfolioAnalysisResponseDTO
from app.dependencies import get_analysis_service
from app.observability import bind_snapshot_id, reset_snapshot_id
from app.services.analysis import AnalysisService

router = APIRouter(prefix="/v1/portfolio", tags=["portfolio"])


@router.post("/analyze", response_model=PortfolioAnalysisResponseDTO)
async def analyze_portfolio(
    request: AnalyzePortfolioRequestDTO,
    analysis_service: Annotated[AnalysisService, Depends(get_analysis_service)],
) -> PortfolioAnalysisResponseDTO:
    snapshot_token = bind_snapshot_id(str(request.snapshot_id))
    try:
        snapshot = request_to_domain(request)
        analysis = await analysis_service.analyze(snapshot)
        return analysis_to_response(analysis)
    finally:
        reset_snapshot_id(snapshot_token)
