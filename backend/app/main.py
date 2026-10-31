"""FastAPI application entrypoint."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_redoc_html, get_swagger_ui_html
from fastapi.responses import JSONResponse

from . import __version__
from .config import settings
from .db import Base, engine
from .errors import install_error_handlers
from .middleware import RateLimitMiddleware, RequestContextMiddleware
from .routers import devices, inventory, matching, projects
from .utils import iso, utcnow

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("tile.api")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if settings.auto_create_tables:
        # Production uses `alembic upgrade head`; this keeps `uvicorn app.main:app`
        # usable for a quick local run and for tests.
        Base.metadata.create_all(bind=engine)
    logger.info("api ready env=%s db=%s", settings.environment, settings.database_url.split("://")[0])
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version=__version__,
        description=(
            "装修瓷砖余料库存与匹配管理后端。\n\n"
            "所有项目级接口都需要 `X-Device-Id` 与 `X-Project-Token` 两个请求头，"
            "服务端逐次校验成员关系，越权返回 403。"
        ),
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=f"{settings.api_prefix}/openapi.json",
    )

    app.add_middleware(RateLimitMiddleware)
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["*"],
        expose_headers=["X-Request-Id", "Content-Disposition"],
    )

    install_error_handlers(app)

    app.include_router(devices.router, prefix=settings.api_prefix)
    app.include_router(projects.router, prefix=settings.api_prefix)
    app.include_router(inventory.router, prefix=settings.api_prefix)
    app.include_router(matching.router, prefix=settings.api_prefix)

    @app.get("/healthz", tags=["system"], summary="健康检查")
    def healthz() -> dict:
        return {"status": "ok", "version": __version__, "time": iso(utcnow())}

    @app.get(f"{settings.api_prefix}/health", tags=["system"])
    def api_health() -> dict:
        return {"status": "ok", "version": __version__, "environment": settings.environment}

    @app.get(f"{settings.api_prefix}/config", tags=["system"], summary="客户端启动配置")
    def client_config() -> dict:
        return {
            "api_version": __version__,
            "server_base_url": settings.public_base_url,
            "default_unit": "mm",
            "units": ["mm", "cm"],
            "min_usable_mm_default": settings.min_usable_mm,
            "max_dimension_mm": settings.max_dimension_mm,
            "max_quantity": settings.max_quantity,
            "cut_options": [
                {"value": "long_side_cut", "label": "长边切到底"},
                {"value": "short_side_cut", "label": "短边切到底"},
            ],
            "remnant_actions": [
                {"value": "store", "label": "直接入库"},
                {"value": "discard", "label": "丢弃"},
            ],
            "notice": "无账号体系：换机或清除应用数据后需重新扫码/输入邀请码加入项目。",
        }

    @app.get("/", include_in_schema=False)
    def root() -> JSONResponse:
        return JSONResponse(
            {
                "name": settings.app_name,
                "version": __version__,
                "docs": "/docs",
                "health": "/healthz",
            }
        )

    @app.get("/docs", include_in_schema=False)
    def swagger_docs():  # noqa: ANN202
        return get_swagger_ui_html(
            openapi_url=app.openapi_url or f"{settings.api_prefix}/openapi.json",
            title=f"{settings.app_name} · API",
        )

    @app.get("/redoc", include_in_schema=False)
    def redoc_docs():  # noqa: ANN202
        return get_redoc_html(
            openapi_url=app.openapi_url or f"{settings.api_prefix}/openapi.json",
            title=f"{settings.app_name} · API",
        )

    return app


app = create_app()
