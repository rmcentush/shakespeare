from __future__ import annotations

import os
from dataclasses import dataclass


class ConfigurationError(RuntimeError):
    pass


def _required(environment: dict[str, str], name: str) -> str:
    value = environment.get(name, "").strip()
    if not value:
        raise ConfigurationError(f"{name} is required")
    return value


def _integer(
    environment: dict[str, str], name: str, default: int, minimum: int, maximum: int
) -> int:
    raw = environment.get(name, str(default))
    try:
        value = int(raw)
    except ValueError as error:
        raise ConfigurationError(f"{name} must be an integer") from error
    if not minimum <= value <= maximum:
        raise ConfigurationError(f"{name} must be between {minimum} and {maximum}")
    return value


@dataclass(frozen=True)
class Settings:
    environment: str
    database_url: str
    oidc_issuer: str
    oidc_audience: str
    oidc_jwks_url: str
    data_retention_days: int = 90
    max_request_bytes: int = 2 * 1024 * 1024

    @classmethod
    def from_environment(cls, values: dict[str, str] | None = None) -> Settings:
        environment = dict(os.environ if values is None else values)
        deployment = environment.get("SHAKESPEARE_ENVIRONMENT", "production").strip().lower()
        if deployment not in {"local", "test", "staging", "production"}:
            raise ConfigurationError(
                "SHAKESPEARE_ENVIRONMENT must be local, test, staging, or production"
            )
        issuer = _required(environment, "SHAKESPEARE_OIDC_ISSUER").rstrip("/")
        jwks_url = _required(environment, "SHAKESPEARE_OIDC_JWKS_URL")
        if deployment in {"staging", "production"} and (
            not issuer.startswith("https://") or not jwks_url.startswith("https://")
        ):
            raise ConfigurationError("OIDC issuer and JWKS URL must use HTTPS outside local/test")
        return cls(
            environment=deployment,
            database_url=_required(environment, "SHAKESPEARE_DATABASE_URL"),
            oidc_issuer=issuer,
            oidc_audience=_required(environment, "SHAKESPEARE_OIDC_AUDIENCE"),
            oidc_jwks_url=jwks_url,
            data_retention_days=_integer(
                environment, "SHAKESPEARE_DATA_RETENTION_DAYS", 90, 1, 365
            ),
            max_request_bytes=_integer(
                environment,
                "SHAKESPEARE_MAX_REQUEST_BYTES",
                2 * 1024 * 1024,
                64 * 1024,
                10 * 1024 * 1024,
            ),
        )

    @property
    def expose_api_docs(self) -> bool:
        return self.environment in {"local", "test"}
