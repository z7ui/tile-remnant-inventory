"""Uniform API error type and exception handlers."""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from .utils import iso, utcnow

CODE_BY_STATUS = {
    400: "bad_request",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    409: "conflict",
    413: "payload_too_large",
    415: "unsupported_media_type",
    422: "validation_error",
    429: "rate_limited",
    500: "internal_error",
}

MESSAGE_BY_STATUS = {
    400: "请求无法处理。",
    401: "缺少或无效的设备凭证。",
    403: "无权访问该项目，请先扫码或输入邀请码加入。",
    404: "资源不存在。",
    405: "请求方法不被支持。",
    409: "数据冲突，请刷新后重试。",
    422: "参数校验失败。",
    429: "请求过于频繁，请稍后再试。",
    500: "服务器内部错误，请稍后重试。",
}


class ApiError(Exception):
    """Domain error carrying a stable machine readable code."""

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details


def error_body(code: str, message: str, details: Any = None, request_id: str = "") -> dict:
    return {
        "error": {
            "code": code,
            "message": message,
            "details": details or {},
            "request_id": request_id,
            "timestamp": iso(utcnow()),
        }
    }


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "") or request.headers.get("x-request-id", "")


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(request: Request, exc: ApiError):  # noqa: ANN202
        return JSONResponse(
            status_code=exc.status_code,
            content=error_body(exc.code, exc.message, exc.details, _request_id(request)),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(request: Request, exc: RequestValidationError):  # noqa: ANN202
        details = []
        for err in exc.errors():
            details.append(
                {
                    "field": ".".join(str(p) for p in err.get("loc", []) if p not in ("body", "query", "path")),
                    "message": err.get("msg", ""),
                    "type": err.get("type", ""),
                }
            )
        return JSONResponse(
            status_code=422,
            content=error_body("validation_error", "参数校验失败，请检查输入。", {"fields": details}, _request_id(request)),
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(request: Request, exc: StarletteHTTPException):  # noqa: ANN202
        code = CODE_BY_STATUS.get(exc.status_code, "error")
        message = exc.detail if isinstance(exc.detail, str) and exc.detail else MESSAGE_BY_STATUS.get(
            exc.status_code, "请求失败。"
        )
        return JSONResponse(
            status_code=exc.status_code,
            content=error_body(code, message, None, _request_id(request)),
        )
