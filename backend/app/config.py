"""Application settings (env driven, never commit real values)."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    app_name: str = "Tile Remnant Inventory API"
    app_version: str = "0.1.1"
    environment: str = "development"
    log_level: str = "INFO"

    # --- storage -----------------------------------------------------------
    database_url: str = "sqlite:///./data/tile_remnant.db"
    data_dir: str = "./data"
    sql_echo: bool = False
    sqlite_busy_timeout_ms: int = 30000
    db_pool_size: int = 10
    db_max_overflow: int = 20

    # --- public address (encoded into the QR payload) -----------------------
    public_base_url: str = "https://tiles.example.com"
    api_prefix: str = "/api"

    # --- security ----------------------------------------------------------
    bcrypt_rounds: int = 12
    device_id_bytes: int = 16
    device_secret_bytes: int = 32
    project_token_bytes: int = 32
    invite_code_length: int = 10
    token_ttl_days: int = 0  # 0 = never expires (long lived project tokens)
    cors_origins: str = "*"
    trust_proxy_headers: bool = True

    # --- rate limiting -----------------------------------------------------
    rate_limit_enabled: bool = True
    rate_limit_per_minute: int = 240
    rate_limit_burst: int = 60
    rate_limit_write_per_minute: int = 60

    # --- domain defaults ---------------------------------------------------
    min_usable_mm: int = 50
    max_dimension_mm: int = 100000
    max_quantity: int = 20000
    default_page_size: int = 20
    max_page_size: int = 200
    auto_create_tables: bool = True

    @property
    def cors_origin_list(self) -> list[str]:
        raw = (self.cors_origins or "").strip()
        if raw in ("", "*"):
            return ["*"]
        return [item.strip() for item in raw.split(",") if item.strip()]


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
