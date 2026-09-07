import asyncio
import json

from app.config import AppSettings, IdempotencyMode
from app.dependencies import build_runtime


async def _run() -> int:
    settings = AppSettings.from_environment()
    if settings.database.idempotency_mode is not IdempotencyMode.DATABASE:
        raise RuntimeError("Cleanup requires ANALYSIS_IDEMPOTENCY_MODE=database.")

    runtime = build_runtime(settings)
    try:
        removed = await runtime.idempotency_store.cleanup_expired()
    finally:
        await runtime.close()
    print(json.dumps({"expired_records_removed": removed}, separators=(",", ":")))
    return 0


def main() -> None:
    raise SystemExit(asyncio.run(_run()))


if __name__ == "__main__":
    main()
