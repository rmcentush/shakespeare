from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Protocol
from uuid import NAMESPACE_URL, UUID, uuid5

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

from .config import Settings


@dataclass(frozen=True)
class Identity:
    tenant_id: UUID
    subject: str


class Verifier(Protocol):
    def verify(self, token: str) -> Identity: ...


class OIDCVerifier:
    _ALGORITHMS = ["RS256", "ES256"]

    def __init__(self, settings: Settings) -> None:
        self._issuer = settings.oidc_issuer
        self._audience = settings.oidc_audience
        self._keys = PyJWKClient(settings.oidc_jwks_url, cache_keys=True, lifespan=300)

    def verify(self, token: str) -> Identity:
        try:
            signing_key = self._keys.get_signing_key_from_jwt(token).key
            claims = jwt.decode(
                token,
                signing_key,
                algorithms=self._ALGORITHMS,
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "iss", "aud", "sub"]},
            )
            subject = claims["sub"]
            if not isinstance(subject, str) or not subject.strip() or len(subject) > 512:
                raise jwt.InvalidTokenError("sub must be a non-empty bounded string")
        except (jwt.PyJWTError, KeyError, TypeError, ValueError) as error:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired access token",
                headers={"WWW-Authenticate": "Bearer"},
            ) from error
        tenant_id = uuid5(NAMESPACE_URL, f"{self._issuer}|{subject}")
        return Identity(tenant_id=tenant_id, subject=subject)


_bearer = HTTPBearer(auto_error=False)


def require_identity(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
) -> Identity:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Bearer access token required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    verifier: Verifier = request.app.state.verifier
    return verifier.verify(credentials.credentials)
