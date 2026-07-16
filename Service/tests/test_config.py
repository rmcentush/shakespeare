from __future__ import annotations

import pytest

from shakespeare_service.config import ConfigurationError, Settings


def environment(**overrides: str) -> dict[str, str]:
    values = {
        "SHAKESPEARE_ENVIRONMENT": "production",
        "SHAKESPEARE_DATABASE_URL": "postgresql://service@database/shakespeare",
        "SHAKESPEARE_OIDC_ISSUER": "https://identity.example",
        "SHAKESPEARE_OIDC_AUDIENCE": "shakespeare-api",
        "SHAKESPEARE_OIDC_JWKS_URL": "https://identity.example/jwks.json",
    }
    values.update(overrides)
    return values


def test_production_identity_metadata_requires_https() -> None:
    with pytest.raises(ConfigurationError, match="HTTPS"):
        Settings.from_environment(
            environment(SHAKESPEARE_OIDC_JWKS_URL="http://identity.example/jwks.json")
        )


def test_retention_is_bounded() -> None:
    with pytest.raises(ConfigurationError, match="between 1 and 365"):
        Settings.from_environment(environment(SHAKESPEARE_DATA_RETENTION_DAYS="1000"))


def test_valid_production_settings_hide_api_docs() -> None:
    settings = Settings.from_environment(environment())
    assert settings.environment == "production"
    assert settings.data_retention_days == 90
    assert not settings.expose_api_docs
