import base64
import asyncio
import csv
import hashlib
import hmac
import io
import json
import logging
import os
import secrets
import smtplib
import threading
import time
from email.message import EmailMessage
from datetime import datetime, timedelta, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv

from fastapi import Depends, FastAPI, Header, HTTPException, Response, status
from fastapi.encoders import jsonable_encoder
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
import paho.mqtt.client as mqtt
from psycopg.types.json import Jsonb

logger = logging.getLogger(__name__)

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except ImportError:  # Push delivery is optional until Firebase Admin is configured.
    firebase_admin = None
    credentials = None
    messaging = None


# ============================================================
# CONFIGURATION
# ============================================================

APP_DIR = os.path.dirname(os.path.abspath(__file__))

# Load backend/.env first, then fill unset values from the project .env.
# .env is located in:
# as_flutter_project/.env
#
# main.py is located in:
# as_flutter_project/backend/app/main.py
#
# Therefore we go up two folders from APP_DIR.
PROJECT_DIR = os.path.dirname(os.path.dirname(APP_DIR))
load_dotenv(os.path.join(PROJECT_DIR, "backend", ".env"))
load_dotenv(os.path.join(PROJECT_DIR, ".env"), override=False)
ENV_PATH = os.path.join(
    os.path.dirname(os.path.dirname(APP_DIR)),
    ".env",
)

load_dotenv(ENV_PATH)

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is missing. Please check the .env file."
    )

MQTT_BROKER = os.getenv("MQTT_BROKER", "").strip()
MQTT_PORT = int(os.getenv("MQTT_PORT", "8883"))
MQTT_USERNAME = os.getenv("MQTT_USERNAME", "")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "")
MQTT_USE_TLS = os.getenv("MQTT_USE_TLS", "true").strip().lower() not in {"0", "false", "no"}

SECRET_KEY = os.getenv(
    "SECRET_KEY",
    "smart-home-dev-secret-key",
)

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24


app = FastAPI(
    title="Smart Home API",
    version="1.0.0",
)

# Flutter Web calls the API from a different origin. Keep the local origins
# available for development and allow deployments to provide their own list.
_default_cors_origins = (
    "http://localhost:8080,http://127.0.0.1:8080,"
    "http://localhost:5000,http://127.0.0.1:5000"
)
CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ALLOWED_ORIGINS", _default_cors_origins).split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer()


# ============================================================
# REQUEST / RESPONSE MODELS
# ============================================================

class RegisterRequest(BaseModel):
    email: str
    password: str = Field(..., min_length=6)
    name: str = Field(..., min_length=1)


class LoginRequest(BaseModel):
    email: str
    password: str = Field(..., min_length=6)


class UserOut(BaseModel):
    id: int
    email: str
    name: str


class AuthTokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class RegisterResponse(BaseModel):
    success: bool
    message: str
    user: UserOut
    requires_email_verification: bool = False


class HealthResponse(BaseModel):
    status: str
    timestamp: str


class ProfileUpdateRequest(BaseModel):
    name: str | None = None
    email: str | None = None


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(..., min_length=6)
    confirm_password: str = Field(..., min_length=6)


class PreferencesPayload(BaseModel):
    notifications_enabled: bool | None = None
    email_alerts: bool | None = None


class ResetPasswordRequest(BaseModel):
    email: str | None = None
    token: str | None = None
    new_password: str | None = None


class DeviceCreateRequest(BaseModel):
    name: str
    type: str = "light"
    pin: int | None = None
    topic: str | None = None


class DeviceUpdateRequest(BaseModel):
    name: str | None = None
    type: str | None = None
    pin: int | None = None
    topic: str | None = None
    status: str | None = None
    is_online: bool | None = None


class LogRequest(BaseModel):
    log_type: str | None = None
    action: str | None = None
    resource_type: str | None = None
    message: str | None = None
    details: Any = Field(default_factory=dict)
    device_id: str | None = None
    resource_id: str | None = None
    severity: str = "info"


class NotificationRequest(BaseModel):
    type: str = Field(..., min_length=1, max_length=80)
    title: str = Field(..., min_length=1, max_length=200)
    message: str = Field(..., min_length=1, max_length=2000)
    metadata: dict[str, Any] = Field(default_factory=dict)


class SensorReadingRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128)
    sensor_type: str = Field(..., min_length=1, max_length=80)
    value: float
    unit: str = Field(default="", max_length=32)
    quality: str = Field(default="good", max_length=32)


class EnergyReadingRequest(BaseModel):
    voltage: float = Field(..., ge=0)
    current: float = Field(..., ge=0)
    power: float = Field(..., ge=0)
    energy: float = Field(..., ge=0)
    timestamp: datetime | None = None
    channels: dict[str, float] = Field(default_factory=dict)


class DeviceSensorItem(BaseModel):
    sensor_type: str = Field(..., min_length=1, max_length=80)
    value: float
    unit: str = Field(default="", max_length=32)


class DeviceSensorBatch(BaseModel):
    readings: list[DeviceSensorItem] = Field(..., min_length=1, max_length=32)


class AlertCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    message: str = Field(..., min_length=1, max_length=2000)
    severity: str = "low"
    source: str = "system"
    device_id: str | None = None


class SensorThresholdsRequest(BaseModel):
    voltage_min: float = Field(..., ge=0)
    voltage_max: float = Field(..., gt=0)
    amperage_max: float = Field(..., gt=0)


class PushTokenRequest(BaseModel):
    token: str = Field(..., min_length=20, max_length=4096)
    platform: str = Field(default="unknown", max_length=32)


class GoogleSignInRequest(BaseModel):
    id_token: str = Field(..., min_length=20)


class TwoFactorCodeRequest(BaseModel):
    email: str = Field(..., min_length=3, max_length=320)
    code: str = Field(..., min_length=6, max_length=6)


class EmailRequest(BaseModel):
    email: str = Field(..., min_length=3, max_length=320)


class EmailVerificationRequest(BaseModel):
    email: str = Field(..., min_length=3, max_length=320)
    code: str = Field(..., min_length=6, max_length=6)


# ============================================================
# TEMPORARY PASSWORD RESET TOKENS
# ============================================================

RESET_TOKENS: dict[str, dict[str, Any]] = {}


# ============================================================
# PASSWORD
# ============================================================

_SCRYPT_N = 1 << 15
_SCRYPT_R = 8
_SCRYPT_P = 1
_SCRYPT_DKLEN = 32


def _hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(
        password.encode("utf-8"), salt=salt, n=_SCRYPT_N, r=_SCRYPT_R,
        p=_SCRYPT_P, maxmem=64 * 1024 * 1024, dklen=_SCRYPT_DKLEN,
    )
    return f"scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${salt.hex()}${digest.hex()}"


def _is_legacy_password_hash(stored_hash: str) -> bool:
    return len(stored_hash) == 64 and all(char in "0123456789abcdefABCDEF" for char in stored_hash)


def _verify_password(password: str, stored_hash: str) -> bool:
    """Verify current scrypt hashes and legacy unsalted SHA-256 hashes."""
    if _is_legacy_password_hash(stored_hash):
        legacy_digest = hashlib.sha256(password.encode("utf-8")).hexdigest()
        return hmac.compare_digest(legacy_digest, stored_hash.lower())

    try:
        algorithm, n_text, r_text, p_text, salt_hex, digest_hex = stored_hash.split("$")
        if algorithm != "scrypt":
            return False
        n, r, p = int(n_text), int(r_text), int(p_text)
        if (n, r, p) != (_SCRYPT_N, _SCRYPT_R, _SCRYPT_P):
            return False
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(digest_hex)
        if len(salt) != 16 or len(expected) != _SCRYPT_DKLEN:
            return False
        actual = hashlib.scrypt(
            password.encode("utf-8"), salt=salt, n=n, r=r, p=p,
            maxmem=64 * 1024 * 1024, dklen=_SCRYPT_DKLEN,
        )
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


# ============================================================
# POSTGRESQL CONNECTION
# ============================================================

def _create_db_connection():
    return psycopg.connect(
        DATABASE_URL,
        row_factory=dict_row,
    )


def _send_push_notification(user_id: int, title: str, message: str,
                            data: dict[str, Any]) -> None:
    """Best-effort FCM delivery; notification records remain available in-app."""
    service_account = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
    if firebase_admin is None or not service_account:
        logger.warning("FCM is not configured: Firebase Admin SDK or service-account credentials are missing")
        return
    try:
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(json.loads(service_account)))
        conn = _create_db_connection()
        try:
            enabled = conn.execute(
                "SELECT notifications_enabled FROM user_preferences WHERE user_id = %s",
                (user_id,),
            ).fetchone()
            if enabled is not None and not enabled["notifications_enabled"]:
                return
            tokens = conn.execute(
                "SELECT token FROM push_device_tokens WHERE user_id = %s", (user_id,)
            ).fetchall()
        finally:
            conn.close()
        for row in tokens:
            try:
                messaging.send(messaging.Message(
                    notification=messaging.Notification(title=title, body=message),
                    data={str(k): str(v) for k, v in data.items()},
                    token=row["token"],
                ))
            except Exception as exc:
                # Remove tokens that Firebase has permanently rejected.
                if "registration-token-not-registered" in str(exc).lower() or "invalid-registration-token" in str(exc).lower():
                    cleanup = _create_db_connection()
                    try:
                        cleanup.execute("DELETE FROM push_device_tokens WHERE token = %s", (row["token"],))
                        cleanup.commit()
                    finally:
                        cleanup.close()
                else:
                    logger.warning("FCM delivery failed for a registered device token: %s", exc)
    except Exception:
        # Push service configuration/outages must not fail notification persistence.
        logger.exception("FCM delivery is unavailable; in-app notifications remain stored")
        return


# ============================================================
# BASE64 HELPERS
# ============================================================

def _encode_base64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(
        b"="
    ).decode("utf-8")


def _decode_base64(token_part: str) -> bytes:
    padding = "=" * (-len(token_part) % 4)

    return base64.urlsafe_b64decode(
        (token_part + padding).encode("utf-8")
    )


# ============================================================
# TOKEN CREATION
# ============================================================

def _create_token(user_id: int, email: str) -> str:
    now = int(time.time())

    payload = {
        "sub": str(user_id),
        "email": email,
        "iat": now,
        "exp": now + ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    }

    payload_json = json.dumps(
        payload,
        separators=(",", ":"),
    ).encode("utf-8")

    encoded_header = _encode_base64(
        b'{"alg":"HS256","typ":"JWT"}'
    )

    encoded_payload = _encode_base64(
        payload_json
    )

    signing_input = (
        f"{encoded_header}.{encoded_payload}"
    ).encode("utf-8")

    signature = hmac.new(
        SECRET_KEY.encode("utf-8"),
        signing_input,
        hashlib.sha256,
    ).digest()

    encoded_signature = _encode_base64(
        signature
    )

    return (
        f"{encoded_header}."
        f"{encoded_payload}."
        f"{encoded_signature}"
    )


def _smtp_configuration() -> tuple[str, int, str, str, str] | None:
    host = os.getenv("SMTP_HOST", "").strip()
    username = os.getenv("SMTP_USER", "").strip()
    password = os.getenv("SMTP_PASS", "")
    sender = os.getenv("EMAIL_FROM", "").strip() or username
    if not host or not username or not password or not sender:
        return None
    try:
        port = int(os.getenv("SMTP_PORT", "587"))
    except ValueError:
        return None
    return host, port, username, password, sender


def _send_email(recipient: str, subject: str, body: str) -> None:
    config = _smtp_configuration()
    if config is None:
        raise RuntimeError("SMTP is not configured")
    host, port, username, password, sender = config
    email = EmailMessage()
    email["From"] = sender
    email["To"] = recipient
    email["Subject"] = subject
    email.set_content(body)
    timeout = float(os.getenv("SMTP_TIMEOUT_SECONDS", "15"))
    if os.getenv("SMTP_USE_SSL", "false").lower() in {"1", "true", "yes"}:
        with smtplib.SMTP_SSL(host, port, timeout=timeout) as server:
            server.login(username, password)
            server.send_message(email)
    else:
        with smtplib.SMTP(host, port, timeout=timeout) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            server.login(username, password)
            server.send_message(email)


def _verify_google_identity_token(token: str) -> dict[str, Any]:
    client_id = os.getenv("GOOGLE_CLIENT_ID", "").strip()
    if not client_id:
        raise HTTPException(status_code=503, detail="Google sign-in is not configured on the server")
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import id_token
        claims = id_token.verify_oauth2_token(token, Request(), audience=client_id)
    except HTTPException:
        raise
    except Exception as exc:
        audience_matches = False
        token_expired: bool | None = None
        try:
            token_parts = token.split(".")
            if len(token_parts) == 3:
                unverified_claims = json.loads(_decode_base64(token_parts[1]))
                aud = unverified_claims.get("aud")
                audience_matches = (
                    client_id == aud
                    or isinstance(aud, list) and client_id in aud
                )
                exp = unverified_claims.get("exp")
                if isinstance(exp, (int, float)):
                    token_expired = exp <= time.time()
        except Exception:
            pass
        logger.warning(
            "Google ID token verification failed: exception=%s audience_matches=%s expired=%s",
            type(exc).__name__, audience_matches, token_expired,
        )
        if not audience_matches:
            raise HTTPException(
                status_code=401,
                detail="Google token audience does not match the backend Web Client ID",
            ) from exc
        if token_expired:
            raise HTTPException(
                status_code=401,
                detail="Google ID token expired; try signing in again",
            ) from exc
        raise HTTPException(status_code=401, detail="Google ID token is invalid or expired") from exc
    if not claims.get("sub") or not claims.get("email") or claims.get("email_verified") not in (True, "true"):
        raise HTTPException(status_code=401, detail="Google account must provide a verified email")
    return claims


def _code_hash(user_id: int, purpose: str, code: str) -> str:
    value = f"{user_id}:{purpose}:{code}".encode("utf-8")
    return hmac.new(SECRET_KEY.encode("utf-8"), value, hashlib.sha256).hexdigest()


def _issue_email_code(user_id: int, email: str, purpose: str) -> None:
    if _smtp_configuration() is None:
        raise HTTPException(status_code=503, detail="Email delivery is not configured on the server")
    conn = _create_db_connection()
    code = f"{secrets.randbelow(1_000_000):06d}"
    digest = _code_hash(user_id, purpose, code)
    try:
        recent = conn.execute(
            "SELECT created_at FROM one_time_codes WHERE user_id = %s AND purpose = %s ORDER BY created_at DESC LIMIT 1",
            (user_id, purpose),
        ).fetchone()
        if recent and (datetime.now(timezone.utc) - recent["created_at"]).total_seconds() < 60:
            raise HTTPException(status_code=429, detail="Please wait before requesting another code")
        conn.execute(
            "DELETE FROM one_time_codes WHERE user_id = %s AND purpose = %s AND consumed_at IS NULL",
            (user_id, purpose),
        )
        conn.execute(
            "INSERT INTO one_time_codes (user_id, purpose, code_hash, expires_at) VALUES (%s, %s, %s, %s)",
            (user_id, purpose, digest, datetime.now(timezone.utc) + timedelta(minutes=10)),
        )
        conn.commit()
    finally:
        conn.close()
    purpose_text = {
        "google_signin_2fa": "sign-in",
        "enable_2fa": "two-factor setup",
        "email_verification": "email verification",
    }.get(purpose, "verification")
    try:
        _send_email(email, "Your Smart Home verification code",
                    f"Your {purpose_text} code is {code}. It expires in 10 minutes. If you did not request it, ignore this email.")
    except Exception as exc:
        cleanup = _create_db_connection()
        try:
            cleanup.execute("DELETE FROM one_time_codes WHERE user_id = %s AND purpose = %s AND code_hash = %s",
                            (user_id, purpose, digest))
            cleanup.commit()
        finally:
            cleanup.close()
        raise HTTPException(status_code=503, detail="Could not send the verification email; check SMTP settings") from exc


def _consume_email_code(user_id: int, purpose: str, code: str) -> bool:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """SELECT id, code_hash, failed_attempts FROM one_time_codes
               WHERE user_id = %s AND purpose = %s AND consumed_at IS NULL AND expires_at > CURRENT_TIMESTAMP
               ORDER BY created_at DESC LIMIT 1""",
            (user_id, purpose),
        ).fetchone()
        if row is None or row["failed_attempts"] >= 5:
            return False
        if not hmac.compare_digest(row["code_hash"], _code_hash(user_id, purpose, code)):
            conn.execute("UPDATE one_time_codes SET failed_attempts = failed_attempts + 1 WHERE id = %s", (row["id"],))
            conn.commit()
            return False
        conn.execute("UPDATE one_time_codes SET consumed_at = CURRENT_TIMESTAMP WHERE id = %s", (row["id"],))
        conn.commit()
        return True
    finally:
        conn.close()


# ============================================================
# TOKEN VERIFICATION
# ============================================================

def _verify_token(token: str) -> dict[str, Any]:
    try:
        header, payload, signature = token.split(".")
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token format",
        ) from exc

    signing_input = (
        f"{header}.{payload}"
    ).encode("utf-8")

    expected_signature = _encode_base64(
        hmac.new(
            SECRET_KEY.encode("utf-8"),
            signing_input,
            hashlib.sha256,
        ).digest()
    )

    if not hmac.compare_digest(
        signature,
        expected_signature,
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token signature",
        )

    try:
        decoded_payload = json.loads(
            _decode_base64(payload)
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Malformed token payload",
        ) from exc

    expired = decoded_payload.get("exp")

    if (
        expired is not None
        and int(expired) < int(time.time())
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
        )

    return decoded_payload


# ============================================================
# USER QUERIES
# ============================================================

def _get_user_by_email(
    email: str,
) -> dict[str, Any] | None:

    conn = _create_db_connection()

    try:
        row = conn.execute(
            """
            SELECT
                id,
                email,
                password_hash,
                name,
                provider,
                two_factor_enabled,
                email_verified
            FROM users
            WHERE email = %s
            """,
            (email.lower(),),
        ).fetchone()

        return row

    finally:
        conn.close()


def _get_user_by_id(
    user_id: int,
) -> dict[str, Any] | None:

    conn = _create_db_connection()

    try:
        row = conn.execute(
            """
            SELECT
                id,
                email,
                name
            FROM users
            WHERE id = %s
            """,
            (user_id,),
        ).fetchone()

        return row

    finally:
        conn.close()


# ============================================================
# CURRENT USER
# ============================================================

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(
        security
    ),
) -> UserOut:

    token = credentials.credentials

    payload = _verify_token(token)

    user_id = payload.get("sub")

    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing subject",
        )

    user = _get_user_by_id(
        int(user_id)
    )

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    return UserOut(
        id=user["id"],
        email=user["email"],
        name=user["name"],
    )


# ============================================================
# HEALTH
# ============================================================

@app.get("/health")
async def health() -> HealthResponse:

    return HealthResponse(
        status="ok",
        timestamp=datetime.now(
            timezone.utc
        ).isoformat(),
    )


# ============================================================
# REGISTER
# ============================================================

@app.post(
    "/auth/register",
    response_model=RegisterResponse,
)
async def register(
    payload: RegisterRequest,
) -> dict[str, Any]:

    email = payload.email.lower().strip()
    name = payload.name.strip()

    if not email or not name:
        raise HTTPException(
            status_code=400,
            detail="Email and name are required",
        )

    existing = _get_user_by_email(email)

    if existing is not None:
        if not existing["email_verified"] and _verify_password(payload.password, existing["password_hash"]):
            if _is_legacy_password_hash(existing["password_hash"]):
                conn = _create_db_connection()
                try:
                    conn.execute("UPDATE users SET password_hash = %s WHERE id = %s",
                                 (_hash_password(payload.password), existing["id"]))
                    conn.commit()
                finally:
                    conn.close()
            await asyncio.to_thread(_issue_email_code, existing["id"], email, "email_verification")
            return {"success": True, "requires_email_verification": True,
                    "message": "A new email verification code was sent.",
                    "user": {"id": existing["id"], "email": email, "name": existing["name"]}}
        raise HTTPException(
            status_code=409,
            detail="User already exists",
        )

    password_hash = _hash_password(
        payload.password
    )

    conn = _create_db_connection()

    try:
        row = conn.execute(
            """
            INSERT INTO users (
                email,
                password_hash,
                name,
                email_verified
            )
            VALUES (%s, %s, %s, FALSE)
            RETURNING id
            """,
            (
                email,
                password_hash,
                name,
            ),
        ).fetchone()

        conn.commit()

        user_id = row["id"]

    finally:
        conn.close()

    try:
        await asyncio.to_thread(_issue_email_code, user_id, email, "email_verification")
    except Exception:
        cleanup = _create_db_connection()
        try:
            cleanup.execute("DELETE FROM users WHERE id = %s AND email_verified = FALSE", (user_id,))
            cleanup.commit()
        finally:
            cleanup.close()
        raise
    return {"success": True, "requires_email_verification": True,
            "message": "A verification code was sent to your email.",
            "user": {"id": user_id, "email": email, "name": name}}


# ============================================================
# LOGIN
# ============================================================

@app.post("/auth/login")
async def login(
    payload: LoginRequest,
) -> dict[str, Any]:

    email = payload.email.lower().strip()

    user_row = _get_user_by_email(email)

    if user_row is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password",
        )

    if not _verify_password(payload.password, user_row["password_hash"]):
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password",
        )

    # Upgrade an existing unsalted SHA-256 hash transparently after successful auth.
    if _is_legacy_password_hash(user_row["password_hash"]):
        conn = _create_db_connection()
        try:
            conn.execute("UPDATE users SET password_hash = %s WHERE id = %s",
                         (_hash_password(payload.password), user_row["id"]))
            conn.commit()
        finally:
            conn.close()

    if not user_row["email_verified"]:
        await asyncio.to_thread(_issue_email_code, user_row["id"], user_row["email"], "email_verification")
        return {"requires_email_verification": True, "email": user_row["email"]}

    if user_row["two_factor_enabled"]:
        await asyncio.to_thread(_issue_email_code, user_row["id"], user_row["email"], "google_signin_2fa")
        return {"requires_2fa": True, "email": user_row["email"],
                "user": {"id": user_row["id"], "email": user_row["email"], "name": user_row["name"]}}

    access_token = _create_token(
        user_row["id"],
        user_row["email"],
    )

    return AuthTokenResponse(
        access_token=access_token,
        token_type="bearer",
        user=UserOut(
            id=user_row["id"],
            email=user_row["email"],
            name=user_row["name"],
        ),
    ).model_dump()


@app.post("/auth/google-signin")
async def google_signin(payload: GoogleSignInRequest) -> dict[str, Any]:
    claims = await asyncio.to_thread(_verify_google_identity_token, payload.id_token)
    email = str(claims["email"]).strip().lower()
    google_subject = str(claims["sub"])
    name = str(claims.get("name") or email.split("@", 1)[0]).strip()
    conn = _create_db_connection()
    try:
        user = conn.execute(
            "SELECT id, email, name, provider, two_factor_enabled, google_subject FROM users WHERE google_subject = %s",
            (google_subject,),
        ).fetchone()
        if user is None:
            user = conn.execute(
                "SELECT id, email, name, provider, two_factor_enabled, google_subject FROM users WHERE email = %s",
                (email,),
            ).fetchone()
            if user is not None and user["google_subject"] not in (None, google_subject):
                raise HTTPException(status_code=409, detail="This email is linked to a different Google account")
            if user is not None and user["google_subject"] is None:
                user = conn.execute(
                    """UPDATE users SET google_subject = %s, provider = 'google', email_verified = TRUE
                       WHERE id = %s RETURNING id, email, name, provider, two_factor_enabled, google_subject""",
                    (google_subject, user["id"]),
                ).fetchone()
                conn.commit()
        if user is None:
            user = conn.execute(
                """INSERT INTO users (email, password_hash, name, provider, google_subject)
                   VALUES (%s, %s, %s, 'google', %s) RETURNING id, email, name, provider, two_factor_enabled, google_subject""",
                (email, secrets.token_hex(32), name, google_subject),
            ).fetchone()
            conn.commit()
        if user["two_factor_enabled"]:
            await asyncio.to_thread(_issue_email_code, user["id"], user["email"], "google_signin_2fa")
            return {"requires_2fa": True, "email": user["email"]}
        token = _create_token(user["id"], user["email"])
        return {"requires_2fa": False, "access_token": token,
                "user": {"id": user["id"], "email": user["email"], "name": user["name"], "provider": user["provider"]}}
    finally:
        conn.close()


@app.post("/auth/request-2fa")
async def request_google_2fa(payload: EmailRequest) -> dict[str, Any]:
    user = _get_user_by_email(payload.email.strip().lower())
    if user is None:
        # Avoid revealing whether an account exists.
        return {"success": True, "message": "If two-factor sign-in is enabled, a code will be sent."}
    conn = _create_db_connection()
    try:
        state = conn.execute("SELECT two_factor_enabled FROM users WHERE id = %s", (user["id"],)).fetchone()
    finally:
        conn.close()
    if state and state["two_factor_enabled"]:
        await asyncio.to_thread(_issue_email_code, user["id"], user["email"], "google_signin_2fa")
    return {"success": True, "message": "If two-factor sign-in is enabled, a code will be sent."}


@app.post("/auth/verify-2fa")
async def verify_google_2fa(payload: TwoFactorCodeRequest) -> dict[str, Any]:
    email = payload.email.strip().lower()
    user = _get_user_by_email(email)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired verification code")
    conn = _create_db_connection()
    try:
        state = conn.execute("SELECT id, email, name, two_factor_enabled FROM users WHERE id = %s", (user["id"],)).fetchone()
    finally:
        conn.close()
    if not state or not state["two_factor_enabled"] or not await asyncio.to_thread(
        _consume_email_code, user["id"], "google_signin_2fa", payload.code
    ):
        raise HTTPException(status_code=401, detail="Invalid or expired verification code")
    return {"success": True, "access_token": _create_token(state["id"], state["email"]),
            "user": {"id": state["id"], "email": state["email"], "name": state["name"]}}


@app.post("/auth/verify-email")
async def verify_email_address(payload: EmailVerificationRequest) -> dict[str, Any]:
    user = _get_user_by_email(payload.email.strip().lower())
    if user is None or user["email_verified"] or not await asyncio.to_thread(
        _consume_email_code, user["id"], "email_verification", payload.code
    ):
        raise HTTPException(status_code=400, detail="Invalid or expired email verification code")
    conn = _create_db_connection()
    try:
        conn.execute("UPDATE users SET email_verified = TRUE WHERE id = %s", (user["id"],))
        conn.commit()
    finally:
        conn.close()
    return {"success": True, "message": "Email verified. You can now sign in."}


@app.get("/settings/2fa/status")
async def two_factor_status(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute("SELECT two_factor_enabled FROM users WHERE id = %s", (current_user.id,)).fetchone()
        return {"enabled": bool(row and row["two_factor_enabled"]), "two_factor_enabled": bool(row and row["two_factor_enabled"])}
    finally:
        conn.close()


@app.post("/settings/2fa/enable")
async def begin_enable_two_factor(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    await asyncio.to_thread(_issue_email_code, current_user.id, current_user.email, "enable_2fa")
    return {"success": True, "pending_verification": True, "message": "Verification code sent to your email"}


@app.post("/settings/2fa/verify")
async def verify_enable_two_factor(payload: dict[str, Any],
                                   current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    code = str(payload.get("code", "")).strip()
    if len(code) != 6 or not code.isdigit() or not await asyncio.to_thread(
        _consume_email_code, current_user.id, "enable_2fa", code
    ):
        raise HTTPException(status_code=400, detail="Invalid or expired verification code")
    conn = _create_db_connection()
    try:
        conn.execute("UPDATE users SET two_factor_enabled = TRUE WHERE id = %s", (current_user.id,))
        conn.commit()
        return {"success": True, "enabled": True}
    finally:
        conn.close()


@app.post("/settings/2fa/disable")
async def disable_two_factor(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        conn.execute("UPDATE users SET two_factor_enabled = FALSE WHERE id = %s", (current_user.id,))
        conn.execute("DELETE FROM one_time_codes WHERE user_id = %s AND purpose IN ('google_signin_2fa', 'enable_2fa')", (current_user.id,))
        conn.commit()
        return {"success": True, "enabled": False}
    finally:
        conn.close()


# ============================================================
# AUTH ME
# ============================================================

@app.get("/auth/me")
async def me(
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    return {
        "user": current_user.model_dump()
    }


# ============================================================
# AUTH USER
# ============================================================

@app.get("/auth/user")
async def get_auth_user(
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute("SELECT provider FROM users WHERE id = %s", (current_user.id,)).fetchone()
    finally:
        conn.close()
    return {
        "id": current_user.id,
        "email": current_user.email,
        "name": current_user.name,
        "provider": row["provider"] if row else "email",
    }


# ============================================================
# PASSWORD RESET REQUEST
# ============================================================

@app.post("/auth/password-reset")
async def request_password_reset(
    payload: ResetPasswordRequest,
) -> dict[str, Any]:

    email = (
        payload.email or ""
    ).strip().lower()

    if not email:
        raise HTTPException(
            status_code=400,
            detail="Email is required",
        )

    if _smtp_configuration() is None:
        raise HTTPException(status_code=503, detail="Email delivery is not configured on the server")

    user = _get_user_by_email(email)

    if user is None:
        return {
            "success": True,
            "message": (
                "If the email exists, "
                "a reset code has been sent."
            ),
        }

    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    conn = _create_db_connection()
    try:
        conn.execute("DELETE FROM password_reset_tokens WHERE user_id = %s", (user["id"],))
        conn.execute(
            "INSERT INTO password_reset_tokens (token_hash, user_id, expires_at) VALUES (%s, %s, %s)",
            (token_hash, user["id"], datetime.now(timezone.utc) + timedelta(minutes=30)),
        )
        conn.commit()
    finally:
        conn.close()
    try:
        await asyncio.to_thread(
            _send_email, email, "Reset your Smart Home password",
            f"Your password reset code is:\n\n{token}\n\nPaste it into the Smart Home app within 30 minutes. If you did not request this, ignore this email.",
        )
    except Exception as exc:
        cleanup = _create_db_connection()
        try:
            cleanup.execute("DELETE FROM password_reset_tokens WHERE token_hash = %s", (token_hash,))
            cleanup.commit()
        finally:
            cleanup.close()
        raise HTTPException(status_code=503, detail="Could not send the reset email; check SMTP settings") from exc

    return {
        "success": True,
        "message": (
            "If the email exists, a reset code has been sent."
        ),
        "token": token,
    }


# ============================================================
# PASSWORD RESET VERIFY
# ============================================================

@app.post("/auth/password-reset/verify")
async def verify_password_reset(
    payload: ResetPasswordRequest,
) -> dict[str, Any]:

    token = (
        payload.token or ""
    ).strip()

    if not token:
        raise HTTPException(
            status_code=400,
            detail="Reset token is required",
        )

    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    conn = _create_db_connection()
    try:
        record = conn.execute(
            """SELECT u.email FROM password_reset_tokens t JOIN users u ON u.id = t.user_id
               WHERE t.token_hash = %s AND t.expires_at > CURRENT_TIMESTAMP""",
            (token_hash,),
        ).fetchone()
    finally:
        conn.close()
    if record is None:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    return {
        "success": True,
        "email": record["email"],
    }


# ============================================================
# PASSWORD RESET CONFIRM
# ============================================================

@app.post("/auth/password-reset/confirm")
async def confirm_password_reset(
    payload: ResetPasswordRequest,
) -> dict[str, Any]:

    token = (
        payload.token or ""
    ).strip()

    email = (
        payload.email or ""
    ).strip().lower()

    new_password = (
        payload.new_password or ""
    ).strip()

    if (
        not new_password
        or len(new_password) < 6
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "New password must be "
                "at least 6 characters"
            ),
        )

    if not token:
        raise HTTPException(
            status_code=400,
            detail="Reset token is required",
        )
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    conn = _create_db_connection()

    try:
        record = conn.execute(
            "SELECT user_id FROM password_reset_tokens WHERE token_hash = %s AND expires_at > CURRENT_TIMESTAMP",
            (token_hash,),
        ).fetchone()
        if record is None:
            raise HTTPException(status_code=400, detail="Invalid or expired reset token")
        conn.execute(
            """
            UPDATE users
            SET password_hash = %s
            WHERE id = %s
            """,
            (
                _hash_password(new_password),
                record["user_id"],
            ),
        )
        conn.execute("DELETE FROM password_reset_tokens WHERE token_hash = %s", (token_hash,))

        conn.commit()

    finally:
        conn.close()

    return {
        "success": True,
        "message": "Password reset successfully",
    }


# ============================================================
# GET PROFILE
# ============================================================

@app.get("/settings/profile")
async def get_profile(
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute("SELECT provider, two_factor_enabled FROM users WHERE id = %s", (current_user.id,)).fetchone()
    finally:
        conn.close()
    return {
        "id": current_user.id,
        "name": current_user.name,
        "email": current_user.email,
        "provider": row["provider"] if row else "email",
        "two_factor_enabled": bool(row and row["two_factor_enabled"]),
    }


# ============================================================
# UPDATE PROFILE
# ============================================================

@app.post("/settings/profile/update")
async def update_profile(
    payload: ProfileUpdateRequest,
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    name = (
        payload.name
        or current_user.name
    ).strip()

    email = (
        payload.email
        or current_user.email
    ).strip().lower()

    if not name:
        raise HTTPException(
            status_code=400,
            detail="Name is required",
        )

    if not email:
        raise HTTPException(
            status_code=400,
            detail="Email is required",
        )

    conn = _create_db_connection()

    try:

        existing = conn.execute(
            """
            SELECT id
            FROM users
            WHERE email = %s
              AND id != %s
            """,
            (
                email,
                current_user.id,
            ),
        ).fetchone()

        if existing is not None:
            raise HTTPException(
                status_code=409,
                detail="Email already in use",
            )

        conn.execute(
            """
            UPDATE users
            SET
                name = %s,
                email = %s
            WHERE id = %s
            """,
            (
                name,
                email,
                current_user.id,
            ),
        )

        conn.commit()

    finally:
        conn.close()

    return {
        "success": True,
        "message": "Profile updated",
        "name": name,
        "email": email,
    }


# ============================================================
# CHANGE PASSWORD
# ============================================================

@app.post("/settings/password/change")
async def change_password(
    payload: ChangePasswordRequest,
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    if (
        payload.new_password
        != payload.confirm_password
    ):
        raise HTTPException(
            status_code=400,
            detail="Passwords do not match",
        )

    user = _get_user_by_email(
        current_user.email
    )

    if user is None:
        raise HTTPException(
            status_code=404,
            detail="User not found",
        )

    if not _verify_password(payload.current_password, user["password_hash"]):
        raise HTTPException(
            status_code=400,
            detail="Current password is incorrect",
        )

    conn = _create_db_connection()

    try:
        conn.execute(
            """
            UPDATE users
            SET password_hash = %s
            WHERE id = %s
            """,
            (
                _hash_password(
                    payload.new_password
                ),
                current_user.id,
            ),
        )

        conn.commit()

    finally:
        conn.close()

    return {
        "success": True,
        "message": "Password changed successfully",
    }


# ============================================================
# GET PREFERENCES
# ============================================================

@app.get("/settings/preferences")
async def get_preferences(
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    conn = _create_db_connection()

    try:

        row = conn.execute(
            """
            SELECT
                notifications_enabled,
                email_alerts
            FROM user_preferences
            WHERE user_id = %s
            """,
            (current_user.id,),
        ).fetchone()

        if row is None:

            conn.execute(
                """
                INSERT INTO user_preferences (
                    user_id,
                    notifications_enabled,
                    email_alerts
                )
                VALUES (%s, TRUE, TRUE)
                """,
                (current_user.id,),
            )

            conn.commit()

            return {
                "notifications_enabled": True,
                "email_alerts": True,
            }

        return {
            "notifications_enabled": bool(
                row["notifications_enabled"]
            ),
            "email_alerts": bool(
                row["email_alerts"]
            ),
        }

    finally:
        conn.close()


# ============================================================
# UPDATE PREFERENCES
# ============================================================

@app.post("/settings/preferences/update")
async def update_preferences(
    payload: PreferencesPayload,
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    conn = _create_db_connection()

    try:

        row = conn.execute(
            """
            SELECT *
            FROM user_preferences
            WHERE user_id = %s
            """,
            (current_user.id,),
        ).fetchone()

        if row is None:

            notifications_enabled = (
                payload.notifications_enabled
                if payload.notifications_enabled
                is not None
                else True
            )

            email_alerts = (
                payload.email_alerts
                if payload.email_alerts
                is not None
                else True
            )

            conn.execute(
                """
                INSERT INTO user_preferences (
                    user_id,
                    notifications_enabled,
                    email_alerts
                )
                VALUES (%s, %s, %s)
                """,
                (
                    current_user.id,
                    notifications_enabled,
                    email_alerts,
                ),
            )

        else:

            notifications_enabled = (
                payload.notifications_enabled
                if payload.notifications_enabled
                is not None
                else bool(
                    row["notifications_enabled"]
                )
            )

            email_alerts = (
                payload.email_alerts
                if payload.email_alerts
                is not None
                else bool(
                    row["email_alerts"]
                )
            )

            conn.execute(
                """
                UPDATE user_preferences
                SET
                    notifications_enabled = %s,
                    email_alerts = %s
                WHERE user_id = %s
                """,
                (
                    notifications_enabled,
                    email_alerts,
                    current_user.id,
                ),
            )

        conn.commit()

    finally:
        conn.close()

    return {
        "success": True,
        "message": "Preferences updated",
    }


# ============================================================
# DELETE ACCOUNT
# ============================================================

@app.delete("/settings/account")
async def delete_account(
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    conn = _create_db_connection()

    try:

        conn.execute(
            """
            DELETE FROM users
            WHERE id = %s
            """,
            (current_user.id,),
        )

        conn.commit()

    finally:
        conn.close()

    return {
        "success": True,
        "message": "Account deleted",
    }


# ============================================================
# LIST DEVICES
# ============================================================

@app.get("/devices/list")
async def list_devices(
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> list[dict[str, Any]]:

    conn = _create_db_connection()

    try:

        rows = conn.execute(
            """
            SELECT *
            FROM devices
            WHERE user_id = %s
            ORDER BY id DESC
            """,
            (current_user.id,),
        ).fetchall()

        return [
            {
                "id": row["id"],
                "name": row["name"],
                "type": row["type"],
                "status": row["status"],
                "is_online": bool(
                    row["is_online"]
                ),
                "pin": row["pin"],
                "topic": row["topic"],
                "created_at": row["created_at"],
                "last_seen": row["last_seen"],
            }
            for row in rows
        ]

    finally:
        conn.close()


# ============================================================
# REGISTER DEVICE
# ============================================================

@app.post("/devices/register")
async def register_device(
    payload: DeviceCreateRequest,
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    conn = _create_db_connection()

    try:

        row = conn.execute(
            """
            INSERT INTO devices (
                user_id,
                name,
                type,
                status,
                is_online,
                pin,
                topic
            )
            VALUES (
                %s,
                %s,
                %s,
                'off',
                TRUE,
                %s,
                %s
            )
            RETURNING *
            """,
            (
                current_user.id,
                payload.name.strip(),
                payload.type.strip() or "light",
                payload.pin,
                payload.topic,
            ),
        ).fetchone()

        conn.commit()

    finally:
        conn.close()

    return {
        "id": row["id"],
        "name": row["name"],
        "type": row["type"],
        "status": row["status"],
        "is_online": bool(
            row["is_online"]
        ),
        "pin": row["pin"],
        "topic": row["topic"],
        "created_at": row["created_at"],
        "last_seen": row["last_seen"],
    }


# ============================================================
# GET SINGLE DEVICE
# ============================================================

@app.get("/devices/{device_id}")
async def get_device(
    device_id: int,
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    conn = _create_db_connection()

    try:

        row = conn.execute(
            """
            SELECT *
            FROM devices
            WHERE id = %s
              AND user_id = %s
            """,
            (
                device_id,
                current_user.id,
            ),
        ).fetchone()

        if row is None:
            raise HTTPException(
                status_code=404,
                detail="Device not found",
            )

        return {
            "id": row["id"],
            "name": row["name"],
            "type": row["type"],
            "status": row["status"],
            "is_online": bool(
                row["is_online"]
            ),
            "pin": row["pin"],
            "topic": row["topic"],
            "created_at": row["created_at"],
            "last_seen": row["last_seen"],
        }

    finally:
        conn.close()


# ============================================================
# UPDATE DEVICE
# ============================================================

@app.patch("/devices/{device_id}")
async def update_device(
    device_id: int,
    payload: DeviceUpdateRequest,
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    conn = _create_db_connection()

    try:

        existing = conn.execute(
            """
            SELECT *
            FROM devices
            WHERE id = %s
              AND user_id = %s
            """,
            (
                device_id,
                current_user.id,
            ),
        ).fetchone()

        if existing is None:
            raise HTTPException(
                status_code=404,
                detail="Device not found",
            )

        updates: list[str] = []
        values: list[Any] = []

        if payload.name is not None:
            updates.append("name = %s")
            values.append(
                payload.name.strip()
            )

        if payload.type is not None:
            updates.append("type = %s")
            values.append(
                payload.type.strip()
            )

        if payload.pin is not None:
            updates.append("pin = %s")
            values.append(payload.pin)

        if payload.topic is not None:
            updates.append("topic = %s")
            values.append(payload.topic)

        if payload.status is not None:
            updates.append("status = %s")
            values.append(payload.status)

        if payload.is_online is not None:
            updates.append("is_online = %s")
            values.append(
                payload.is_online
            )

        if not updates:
            raise HTTPException(
                status_code=400,
                detail="No fields to update",
            )

        values.extend(
            [
                device_id,
                current_user.id,
            ]
        )

        query = f"""
            UPDATE devices
            SET {", ".join(updates)}
            WHERE id = %s
              AND user_id = %s
        """

        conn.execute(
            query,
            values,
        )

        conn.commit()

        row = conn.execute(
            """
            SELECT *
            FROM devices
            WHERE id = %s
              AND user_id = %s
            """,
            (
                device_id,
                current_user.id,
            ),
        ).fetchone()

        return {
            "id": row["id"],
            "name": row["name"],
            "type": row["type"],
            "status": row["status"],
            "is_online": bool(
                row["is_online"]
            ),
            "pin": row["pin"],
            "topic": row["topic"],
            "created_at": row["created_at"],
            "last_seen": row["last_seen"],
        }

    finally:
        conn.close()


# ============================================================
# DELETE DEVICE
# ============================================================

@app.delete("/devices/{device_id}")
async def delete_device(
    device_id: int,
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    conn = _create_db_connection()

    try:

        cursor = conn.execute(
            """
            DELETE FROM devices
            WHERE id = %s
              AND user_id = %s
            """,
            (
                device_id,
                current_user.id,
            ),
        )

        conn.commit()

        if cursor.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail="Device not found",
            )

    finally:
        conn.close()

    return {
        "success": True,
        "message": "Device deleted",
    }


# ============================================================
# CONTROL DEVICE
# ============================================================

def _publish_mqtt_message(topic: str, message: str) -> None:
    if not MQTT_BROKER or not MQTT_USERNAME or not MQTT_PASSWORD:
        raise RuntimeError("MQTT publisher is not configured")
    connected = threading.Event()
    connect_error: list[str] = []
    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"smart-home-api-{secrets.token_hex(8)}",
        protocol=mqtt.MQTTv311,
    )
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    if MQTT_USE_TLS:
        client.tls_set()

    def on_connect(_client: Any, _userdata: Any, _flags: Any, reason_code: Any, _properties: Any) -> None:
        if reason_code != 0:
            connect_error.append(str(reason_code))
        connected.set()

    client.on_connect = on_connect
    loop_started = False
    try:
        if client.connect(MQTT_BROKER, MQTT_PORT, keepalive=15) != mqtt.MQTT_ERR_SUCCESS:
            raise RuntimeError("MQTT connection could not be started")
        client.loop_start()
        loop_started = True
        if not connected.wait(timeout=8) or connect_error:
            raise TimeoutError("MQTT broker connection failed")
        info = client.publish(topic, message, qos=1, retain=False)
        if info.rc != mqtt.MQTT_ERR_SUCCESS:
            raise RuntimeError("MQTT publish could not be started")
        info.wait_for_publish(timeout=8)
        if not info.is_published():
            raise TimeoutError("MQTT publish timed out")
    finally:
        if client.is_connected():
            client.disconnect()
        if loop_started:
            client.loop_stop()


def _execute_device_command(user_id: int, selector: str, command: str) -> dict[str, Any]:
    requested = command.strip().lower()
    if requested not in {"on", "off", "turn_on", "turn_off", "toggle"}:
        raise HTTPException(status_code=400, detail="Unsupported command")
    conn = _create_db_connection()
    try:
        device = conn.execute(
            """SELECT id, user_id, name, status, mqtt_client_id FROM devices
               WHERE user_id = %s AND (id::text = %s OR mqtt_client_id = %s) LIMIT 1""",
            (user_id, selector, selector),
        ).fetchone()
        if device is None:
            raise HTTPException(status_code=404, detail="Device not found")
        mqtt_id = str(device["mqtt_client_id"] or device["id"]).strip()
        if not mqtt_id or any(char in mqtt_id for char in "/+#"):
            raise HTTPException(status_code=400, detail="Device MQTT ID is invalid")
        previous = str(device["status"] or "unknown").lower()
        if requested == "toggle":
            target = "off" if previous == "on" else "on"
        else:
            target = "off" if requested in {"off", "turn_off"} else "on"
        topic = f"home/device/{mqtt_id}/set"
        details = {"resource_type": "device", "device_name": device["name"],
                   "command": target.upper(), "previous_state": previous,
                   "new_state": target, "success": False, "status": "pending",
                   "mqtt_topic": topic, "mqtt_device_id": mqtt_id}
        event = conn.execute(
            """INSERT INTO activity_logs (user_id, log_type, message, device_id, severity, details)
               VALUES (%s, 'device_control', %s, %s, 'info', %s) RETURNING id""",
            (user_id, f"{device['name']}: {target.upper()} command pending", str(device["id"]), Jsonb(details)),
        ).fetchone()
        conn.commit()
        event_id = event["id"]
    finally:
        conn.close()

    try:
        _publish_mqtt_message(topic, target.upper())
    except Exception as exc:
        details.update({"success": False, "status": "failed", "error_message": str(exc)})
        conn = _create_db_connection()
        try:
            conn.execute(
                """UPDATE activity_logs SET message = %s, severity = 'error', details = %s
                   WHERE id = %s AND user_id = %s AND details->>'status' <> 'acknowledged'""",
                (f"{device['name']}: {target.upper()} command failed", Jsonb(details), event_id, user_id),
            )
            conn.commit()
        finally:
            conn.close()
        raise HTTPException(status_code=502, detail="Could not publish device command to MQTT") from exc

    details.update({"success": True, "status": "published"})
    conn = _create_db_connection()
    try:
        conn.execute(
            """UPDATE activity_logs SET message = %s, details = %s
               WHERE id = %s AND user_id = %s AND details->>'status' = 'pending'""",
            (f"{device['name']}: {target.upper()} command published", Jsonb(details), event_id, user_id),
        )
        conn.commit()
    finally:
        conn.close()
    return {"success": True, "message": "Device command published",
            "mqtt_published": True, "topic": topic, "new_status": target}


def _record_mqtt_state(topic: str, payload: bytes) -> None:
    parts = topic.split("/")
    if len(parts) != 4 or parts[:2] != ["home", "device"] or parts[3] != "state":
        return
    mqtt_id = parts[2]
    try:
        state = payload.decode("utf-8").strip().upper()
        if state.startswith("{"):
            state = str(json.loads(state).get("state", "")).strip().upper()
    except (UnicodeDecodeError, json.JSONDecodeError):
        return
    if state not in {"ON", "OFF"}:
        return

    conn = _create_db_connection()
    try:
        device = conn.execute(
            "SELECT id, user_id, name, status FROM devices WHERE mqtt_client_id = %s LIMIT 1",
            (mqtt_id,),
        ).fetchone()
        if device is None:
            return
        previous = str(device["status"] or "unknown").lower()
        target = state.lower()
        conn.execute(
            "UPDATE devices SET status = %s, is_online = TRUE, last_seen = CURRENT_TIMESTAMP WHERE id = %s",
            (target, device["id"]),
        )
        pending = conn.execute(
            """SELECT id, details FROM activity_logs
               WHERE user_id = %s AND log_type = 'device_control' AND device_id = %s
                 AND details->>'new_state' = %s AND details->>'status' IN ('pending', 'published')
                 AND created_at >= CURRENT_TIMESTAMP - INTERVAL '5 minutes'
               ORDER BY created_at DESC LIMIT 1""",
            (device["user_id"], str(device["id"]), target),
        ).fetchone()
        if pending is not None:
            details = dict(pending["details"] or {})
            details.update({"success": True, "status": "acknowledged",
                            "acknowledged_at": datetime.now(timezone.utc).isoformat(),
                            "reported_state": target})
            conn.execute(
                "UPDATE activity_logs SET message = %s, details = %s WHERE id = %s",
                (f"{device['name']}: {state} command acknowledged", Jsonb(details), pending["id"]),
            )
        elif previous != target:
            details = {"resource_type": "device", "device_name": device["name"],
                       "command": state, "previous_state": previous, "new_state": target,
                       "success": True, "status": "reported", "source": "mqtt_state",
                       "mqtt_topic": topic}
            conn.execute(
                """INSERT INTO activity_logs (user_id, log_type, message, device_id, severity, details)
                   VALUES (%s, 'device_control', %s, %s, 'info', %s)""",
                (device["user_id"], f"{device['name']}: state changed to {state}",
                 str(device["id"]), Jsonb(details)),
            )
        conn.commit()
    finally:
        conn.close()


_mqtt_event_client: mqtt.Client | None = None


@app.on_event("startup")
async def start_mqtt_event_listener() -> None:
    global _mqtt_event_client
    if not MQTT_BROKER or not MQTT_USERNAME or not MQTT_PASSWORD:
        return
    client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                         client_id=f"smart-home-events-{secrets.token_hex(6)}",
                         protocol=mqtt.MQTTv311)
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    if MQTT_USE_TLS:
        client.tls_set()

    def on_connect(mqtt_client: Any, _userdata: Any, _flags: Any,
                   reason_code: Any, _properties: Any) -> None:
        if reason_code == 0:
            mqtt_client.subscribe("home/device/+/state", qos=1)

    def on_message(_mqtt_client: Any, _userdata: Any, message: Any) -> None:
        try:
            _record_mqtt_state(message.topic, message.payload)
        except Exception as exc:
            print(f"MQTT state event persistence failed: {exc}")

    client.on_connect = on_connect
    client.on_message = on_message
    client.connect_async(MQTT_BROKER, MQTT_PORT, keepalive=30)
    client.loop_start()
    _mqtt_event_client = client


@app.on_event("shutdown")
async def stop_mqtt_event_listener() -> None:
    global _mqtt_event_client
    if _mqtt_event_client is not None:
        _mqtt_event_client.disconnect()
        _mqtt_event_client.loop_stop()
        _mqtt_event_client = None

@app.post("/devices/{device_id}/control")
async def control_device(
    device_id: int,
    body: dict[str, Any],
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:
    return await asyncio.to_thread(
        _execute_device_command, current_user.id, str(device_id),
        str(body.get("command", body.get("action", ""))),
    )


@app.post("/devices/control")
async def control_device_legacy(payload: dict[str, Any],
                                current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    selector = str(payload.get("device_id", "")).strip()
    return await asyncio.to_thread(
        _execute_device_command, current_user.id, selector,
        str(payload.get("action", payload.get("command", ""))),
    )


def _notification_json(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(row["id"]), "user_id": str(row["user_id"]),
        "type": row["type"], "title": row["title"],
        "message": row["message"], "metadata": row["metadata"] or {},
        "is_read": bool(row["is_read"]), "isRead": bool(row["is_read"]),
        "created_at": row["created_at"], "timestamp": row["created_at"],
    }


@app.get("/notifications")
async def list_notifications(limit: int = 100,
                             current_user: UserOut = Depends(get_current_user)) -> list[dict[str, Any]]:
    conn = _create_db_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM notifications WHERE user_id = %s ORDER BY created_at DESC, id DESC LIMIT %s",
            (current_user.id, max(1, min(limit, 100))),
        ).fetchall()
        return [_notification_json(row) for row in rows]
    finally:
        conn.close()


@app.post("/notifications")
async def create_notification(payload: NotificationRequest,
                              current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """INSERT INTO notifications (user_id, type, title, message, metadata)
               VALUES (%s, %s, %s, %s, %s) RETURNING *""",
            (current_user.id, payload.type, payload.title, payload.message, Jsonb(payload.metadata)),
        ).fetchone()
        conn.commit()
    finally:
        conn.close()
    await asyncio.to_thread(_send_push_notification, current_user.id, payload.title,
                            payload.message, {"notification_id": str(row["id"]), "type": payload.type})
    return _notification_json(row)


@app.patch("/notifications/{notification_id}/read")
async def mark_notification_read(notification_id: int,
                                 current_user: UserOut = Depends(get_current_user)) -> dict[str, bool]:
    conn = _create_db_connection()
    try:
        conn.execute("UPDATE notifications SET is_read = TRUE WHERE id = %s AND user_id = %s",
                     (notification_id, current_user.id))
        conn.commit()
        return {"success": True}
    finally:
        conn.close()


@app.post("/notifications/read-all")
async def mark_all_notifications_read(current_user: UserOut = Depends(get_current_user)) -> dict[str, bool]:
    conn = _create_db_connection()
    try:
        conn.execute("UPDATE notifications SET is_read = TRUE WHERE user_id = %s", (current_user.id,))
        conn.commit()
        return {"success": True}
    finally:
        conn.close()


@app.delete("/notifications/{notification_id}")
async def delete_notification(notification_id: int,
                              current_user: UserOut = Depends(get_current_user)) -> dict[str, bool]:
    conn = _create_db_connection()
    try:
        conn.execute("DELETE FROM notifications WHERE id = %s AND user_id = %s",
                     (notification_id, current_user.id))
        conn.commit()
        return {"success": True}
    finally:
        conn.close()


@app.delete("/notifications")
async def delete_all_notifications(current_user: UserOut = Depends(get_current_user)) -> dict[str, bool]:
    conn = _create_db_connection()
    try:
        conn.execute("DELETE FROM notifications WHERE user_id = %s", (current_user.id,))
        conn.commit()
        return {"success": True}
    finally:
        conn.close()


@app.post("/notifications/device-token")
async def register_push_token(payload: PushTokenRequest,
                              current_user: UserOut = Depends(get_current_user)) -> dict[str, bool]:
    conn = _create_db_connection()
    try:
        conn.execute(
            """INSERT INTO push_device_tokens (user_id, token, platform, updated_at)
               VALUES (%s, %s, %s, CURRENT_TIMESTAMP)
               ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id,
                   platform = EXCLUDED.platform, updated_at = CURRENT_TIMESTAMP""",
            (current_user.id, payload.token, payload.platform),
        )
        conn.commit()
        return {"success": True}
    finally:
        conn.close()


@app.delete("/notifications/device-token")
async def unregister_push_token(payload: PushTokenRequest,
                                current_user: UserOut = Depends(get_current_user)) -> dict[str, bool]:
    conn = _create_db_connection()
    try:
        conn.execute("DELETE FROM push_device_tokens WHERE user_id = %s AND token = %s",
                     (current_user.id, payload.token))
        conn.commit()
        return {"success": True}
    finally:
        conn.close()


def _log_json(row: dict[str, Any]) -> dict[str, Any]:
    details = row["details"] or {}
    return {
        "id": str(row["id"]), "user_id": str(row["user_id"]),
        "action": row["log_type"], "log_type": row["log_type"],
        "resource_type": details.get("resource_type", ""),
        "resource_id": row["device_id"], "device_id": row["device_id"],
        "device_name": details.get("device_name") or str(row["message"]).split(":", 1)[0],
        "message": row["message"], "details": row["message"],
        "metadata": details, "severity": row["severity"],
        "ip_address": "", "created_at": row["created_at"],
        "timestamp": row["created_at"], "command": details.get("command", ""),
        "previous_state": details.get("previous_state", "unknown"),
        "new_state": details.get("new_state", "unknown"),
        "success": details.get("success", True),
        "error_message": details.get("error_message"),
    }


def _fetch_logs(user_id: int, *, limit: int, offset: int, log_type: str | None = None,
                severity: str | None = None, device_id: str | None = None,
                hours: int | None = None, start_time: datetime | None = None,
                end_time: datetime | None = None) -> tuple[list[dict[str, Any]], int]:
    conditions = ["user_id = %s"]
    values: list[Any] = [user_id]
    for column, value in (("log_type", log_type), ("severity", severity), ("device_id", device_id)):
        if value is not None:
            conditions.append(f"{column} = %s")
            values.append(value)
    if hours is not None:
        conditions.append("created_at >= CURRENT_TIMESTAMP - (%s * INTERVAL '1 hour')")
        values.append(max(1, hours))
    if start_time is not None:
        conditions.append("created_at >= %s")
        values.append(start_time)
    if end_time is not None:
        conditions.append("created_at <= %s")
        values.append(end_time)
    where_sql = " AND ".join(conditions)
    conn = _create_db_connection()
    try:
        total = conn.execute(f"SELECT COUNT(*) AS total FROM activity_logs WHERE {where_sql}", values).fetchone()["total"]
        rows = conn.execute(
            f"SELECT * FROM activity_logs WHERE {where_sql} ORDER BY created_at DESC LIMIT %s OFFSET %s",
            [*values, max(1, min(limit, 1000)), max(0, offset)],
        ).fetchall()
        return [_log_json(row) for row in rows], total
    finally:
        conn.close()


@app.get("/logs/list")
async def list_logs(limit: int = 50, skip: int = 0, offset: int | None = None,
                    hours: int | None = None, log_type: str | None = None,
                    severity: str | None = None,
                    current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    logs, total = await asyncio.to_thread(
        _fetch_logs, current_user.id, limit=limit,
        offset=skip if offset is None else offset, hours=hours,
        log_type=log_type, severity=severity,
    )
    return {"logs": logs, "total": total, "count": total}


@app.get("/logs/user")
async def list_user_logs(limit: int = 50, offset: int = 0, log_type: str | None = None,
                         action: str | None = None, resource_type: str | None = None,
                         start_time: datetime | None = None, end_time: datetime | None = None,
                         hours: int | None = None,
                         current_user: UserOut = Depends(get_current_user)) -> list[dict[str, Any]]:
    logs, _ = await asyncio.to_thread(
        _fetch_logs, current_user.id, limit=limit, offset=offset, hours=hours,
        log_type=log_type or action, start_time=start_time, end_time=end_time,
    )
    if resource_type:
        logs = [entry for entry in logs if entry["resource_type"] == resource_type]
    return logs


@app.get("/logs/device/{device_id}")
async def list_device_logs(device_id: str, limit: int = 100, offset: int = 0,
                           hours: int | None = None, errors_only: bool = False,
                           current_user: UserOut = Depends(get_current_user)) -> list[dict[str, Any]]:
    selector = device_id
    if not selector.isdigit():
        conn = _create_db_connection()
        try:
            device = conn.execute(
                "SELECT id FROM devices WHERE user_id = %s AND mqtt_client_id = %s LIMIT 1",
                (current_user.id, selector),
            ).fetchone()
            if device is None:
                return []
            selector = str(device["id"])
        finally:
            conn.close()
    logs, _ = await asyncio.to_thread(
        _fetch_logs, current_user.id, limit=limit, offset=offset,
        device_id=selector, hours=hours,
    )
    return [entry for entry in logs if not errors_only or entry["severity"] == "error"]


@app.get("/logs/statistics")
async def get_log_statistics(days_back: int = 30,
                             current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        total = conn.execute(
            "SELECT COUNT(*) AS total FROM activity_logs WHERE user_id = %s AND created_at >= CURRENT_TIMESTAMP - (%s * INTERVAL '1 day')",
            (current_user.id, max(1, days_back)),
        ).fetchone()["total"]
        return {"total": total, "days": max(1, days_back)}
    finally:
        conn.close()


@app.post("/logs/create")
async def create_log(payload: LogRequest,
                     current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    log_type = payload.log_type or payload.action or "activity"
    message = payload.message or (payload.details if isinstance(payload.details, str) else str(payload.details))
    details = payload.details if isinstance(payload.details, dict) else {
        "details": payload.details, "resource_type": payload.resource_type,
    }
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """INSERT INTO activity_logs (user_id, log_type, message, device_id, severity, details)
               VALUES (%s, %s, %s, %s, %s, %s) RETURNING *""",
            (current_user.id, log_type, str(message), payload.device_id or payload.resource_id,
             payload.severity, Jsonb(details)),
        ).fetchone()
        conn.commit()
        return _log_json(row)
    finally:
        conn.close()


@app.get("/logs/export")
async def export_logs(format: str = "json", start_time: datetime | None = None,
                      end_time: datetime | None = None,
                      current_user: UserOut = Depends(get_current_user)) -> Response:
    export_format = format.strip().lower()
    if export_format not in {"json", "csv"}:
        raise HTTPException(status_code=400, detail="Format must be json or csv")
    logs, _ = await asyncio.to_thread(
        _fetch_logs, current_user.id, limit=1000, offset=0,
        start_time=start_time, end_time=end_time,
    )
    if export_format == "csv":
        output = io.StringIO()
        columns = ("id", "action", "message", "device_id", "severity", "created_at")
        writer = csv.DictWriter(output, fieldnames=columns)
        writer.writeheader()
        writer.writerows([{key: entry.get(key) for key in columns} for entry in logs])
        return Response(content=output.getvalue(), media_type="text/csv")
    return JSONResponse(content=jsonable_encoder(logs))


@app.delete("/logs/clear-old")
async def clear_old_logs(days_old: int = 90,
                         current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        cursor = conn.execute(
            "DELETE FROM activity_logs WHERE user_id = %s AND created_at < CURRENT_TIMESTAMP - (%s * INTERVAL '1 day')",
            (current_user.id, max(1, days_old)),
        )
        conn.commit()
        return {"success": True, "deleted": cursor.rowcount}
    finally:
        conn.close()


# ============================================================
# ENERGY, SENSOR HISTORY, THRESHOLDS, AND ALERTS
# ============================================================

def _require_device_ingest_key(provided_key: str | None) -> None:
    configured_key = os.getenv("DEVICE_INGEST_API_KEY", "").strip()
    if not configured_key:
        raise HTTPException(status_code=503, detail="Device ingestion is not configured")
    if not provided_key or not hmac.compare_digest(provided_key, configured_key):
        raise HTTPException(status_code=401, detail="Invalid device API key")


def _device_owner(conn: Any, device_id: str) -> tuple[int, str]:
    row = conn.execute(
        "SELECT id, user_id FROM devices WHERE id::text = %s LIMIT 1",
        (device_id.strip(),),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Device is not registered")
    return int(row["user_id"]), str(row["id"])


@app.post("/ingest/energy")
async def ingest_device_energy(
    payload: EnergyReadingRequest,
    device_id: str,
    x_device_api_key: str | None = Header(default=None, alias="X-Device-API-Key"),
) -> dict[str, Any]:
    _require_device_ingest_key(x_device_api_key)
    conn = _create_db_connection()
    pending_pushes: list[dict[str, Any]] = []
    try:
        user_id, canonical_device_id = _device_owner(conn, device_id)
        timestamp = payload.timestamp or datetime.now(timezone.utc)
        row = conn.execute(
            """INSERT INTO energy_readings (user_id, voltage, current, power, energy, channels, recorded_at)
               VALUES (%s, %s, %s, %s, %s, %s, %s)
               RETURNING voltage, current, power, energy, channels, recorded_at AS timestamp""",
            (user_id, payload.voltage, payload.current, payload.power, payload.energy,
             Jsonb(payload.channels), timestamp),
        ).fetchone()
        for sensor_type, value, unit in (("voltage", payload.voltage, "V"),
                                         ("current", payload.current, "A"),
                                         ("power", payload.power, "W"),
                                         ("energy", payload.energy, "kWh")):
            conn.execute(
                """INSERT INTO sensor_readings (user_id, device_id, sensor_type, value, unit)
                   VALUES (%s, %s, %s, %s, %s)""",
                (user_id, canonical_device_id, sensor_type, value, unit),
            )
            push = _evaluate_sensor_thresholds(conn, user_id, canonical_device_id, sensor_type, value)
            if push:
                pending_pushes.append(push)
        conn.execute("UPDATE devices SET is_online = TRUE, last_seen = CURRENT_TIMESTAMP WHERE id = %s",
                     (canonical_device_id,))
        conn.commit()
        result = dict(row)
    finally:
        conn.close()
    for push in pending_pushes:
        await asyncio.to_thread(_send_push_notification, user_id,
                                push["title"], push["message"], push["metadata"])
    return {"success": True, "device_id": canonical_device_id, "reading": result}


@app.post("/ingest/sensors")
async def ingest_device_sensors(
    payload: DeviceSensorBatch,
    device_id: str,
    x_device_api_key: str | None = Header(default=None, alias="X-Device-API-Key"),
) -> dict[str, Any]:
    _require_device_ingest_key(x_device_api_key)
    conn = _create_db_connection()
    pending_pushes: list[dict[str, Any]] = []
    try:
        user_id, canonical_device_id = _device_owner(conn, device_id)
        for reading in payload.readings:
            sensor_type = reading.sensor_type.strip().lower()
            conn.execute(
                """INSERT INTO sensor_readings (user_id, device_id, sensor_type, value, unit)
                   VALUES (%s, %s, %s, %s, %s)""",
                (user_id, canonical_device_id, sensor_type, reading.value, reading.unit),
            )
            push = _evaluate_sensor_thresholds(conn, user_id, canonical_device_id,
                                               sensor_type, reading.value)
            if push:
                pending_pushes.append(push)
        conn.execute("UPDATE devices SET is_online = TRUE, last_seen = CURRENT_TIMESTAMP WHERE id = %s",
                     (canonical_device_id,))
        conn.commit()
    finally:
        conn.close()
    for push in pending_pushes:
        await asyncio.to_thread(_send_push_notification, user_id,
                                push["title"], push["message"], push["metadata"])
    return {"success": True, "device_id": canonical_device_id,
            "stored": len(payload.readings)}

def _owned_device_id(conn: Any, user_id: int, selector: str) -> str:
    row = conn.execute(
        """SELECT id FROM devices WHERE user_id = %s
           AND (id::text = %s OR mqtt_client_id = %s) LIMIT 1""",
        (user_id, selector.strip(), selector.strip()),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Device not found")
    return str(row["id"])


def _sensor_json(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(row["id"]), "device_id": str(row["device_id"] or ""),
        "sensor_type": row["sensor_type"], "value": row["value"],
        "unit": row["unit"], "quality": row["quality"],
        "timestamp": row["recorded_at"].isoformat(), "metadata": {},
    }


def _alert_json(row: dict[str, Any]) -> dict[str, Any]:
    resolved = bool(row["resolved"])
    return {
        "id": str(row["id"]), "title": row["title"], "message": row["message"],
        "severity": row["severity"], "source": row["source"],
        "device_id": str(row["device_id"]) if row["device_id"] is not None else None,
        "is_read": bool(row["is_read"]), "is_dismissed": resolved,
        "resolved": resolved, "is_resolved": resolved,
        "created_at": row["created_at"].isoformat(), "acknowledged_at": None,
        "metadata": row["metadata"] or {},
    }


def _insert_alert(conn: Any, user_id: int, *, title: str, message: str,
                  severity: str, source: str, device_id: str | None,
                  metadata: dict[str, Any]) -> dict[str, Any]:
    return conn.execute(
        """INSERT INTO alerts (user_id, title, message, severity, source, device_id, metadata)
           VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING *""",
        (user_id, title, message, severity, source, device_id, Jsonb(metadata)),
    ).fetchone()


def _insert_alert_notification(conn: Any, user_id: int, row: dict[str, Any]) -> None:
    conn.execute(
        """INSERT INTO notifications (user_id, type, title, message, metadata)
           VALUES (%s, 'alert', %s, %s, %s)""",
        (user_id, row["title"], row["message"],
         Jsonb({"alert_id": str(row["id"]), "severity": row["severity"], "source": row["source"]})),
    )


def _evaluate_sensor_thresholds(conn: Any, user_id: int, device_id: str,
                                sensor_type: str, value: float) -> dict[str, Any] | None:
    kind = sensor_type.strip().lower()
    prefs = conn.execute(
        """SELECT voltage_min, voltage_max, amperage_max, sensor_thresholds_configured
           FROM user_preferences WHERE user_id = %s""", (user_id,),
    ).fetchone()
    if not prefs or not prefs["sensor_thresholds_configured"]:
        return None

    violation: tuple[str, str, str] | None = None
    if kind in {"voltage", "voltage_v", "volts"}:
        if value < prefs["voltage_min"]:
            violation = ("Voltage below limit", f"Voltage {value:g} V is below the minimum {prefs['voltage_min']:g} V.", "high")
        elif value > prefs["voltage_max"]:
            violation = ("Voltage above limit", f"Voltage {value:g} V exceeds the maximum {prefs['voltage_max']:g} V.", "high")
    elif kind in {"current", "amperage", "current_a", "amps"} and value > prefs["amperage_max"]:
        severity = "critical" if value > prefs["amperage_max"] * 1.2 else "high"
        violation = ("Current above limit", f"Current {value:g} A exceeds the maximum {prefs['amperage_max']:g} A.", severity)

    if violation is None:
        conn.execute(
            """UPDATE alerts SET resolved = TRUE, is_read = TRUE
               WHERE user_id = %s AND source = 'sensor' AND device_id = %s
                 AND metadata->>'sensor_type' = %s AND resolved = FALSE""",
            (user_id, device_id, kind),
        )
        return None

    open_alert = conn.execute(
        """SELECT id FROM alerts WHERE user_id = %s AND source = 'sensor' AND device_id = %s
           AND metadata->>'sensor_type' = %s AND resolved = FALSE LIMIT 1""",
        (user_id, device_id, kind),
    ).fetchone()
    if open_alert:
        return None
    title, message, severity = violation
    row = _insert_alert(
        conn, user_id, title=title, message=message, severity=severity,
        source="sensor", device_id=device_id,
        metadata={"sensor_type": kind, "value": value},
    )
    _insert_alert_notification(conn, user_id, row)
    return {"title": title, "message": message,
            "metadata": {"alert_id": str(row["id"]), "severity": severity, "source": "sensor"}}


@app.post("/devices/register-energy")
async def register_energy_device(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """SELECT id, name, type, status, is_online, mqtt_client_id
               FROM devices WHERE user_id = %s AND lower(name) = 'energy monitor'
               ORDER BY id LIMIT 1""", (current_user.id,),
        ).fetchone()
        if row is None:
            row = conn.execute(
                """INSERT INTO devices (user_id, name, type, status, is_online)
                   VALUES (%s, 'Energy Monitor', 'energy_monitor', 'online', TRUE)
                   RETURNING id, name, type, status, is_online, mqtt_client_id""",
                (current_user.id,),
            ).fetchone()
            conn.commit()
        return {"success": True, "device": dict(row), "device_id": str(row["id"])}
    finally:
        conn.close()


@app.get("/energy/current")
async def get_current_energy(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """SELECT voltage, current, power, energy, channels, recorded_at AS timestamp
               FROM energy_readings WHERE user_id = %s ORDER BY recorded_at DESC, id DESC LIMIT 1""",
            (current_user.id,),
        ).fetchone()
        return dict(row) if row else {}
    finally:
        conn.close()


@app.get("/energy/history")
async def get_energy_history(limit: int = 100, start_time: datetime | None = None,
                             end_time: datetime | None = None,
                             current_user: UserOut = Depends(get_current_user)) -> list[dict[str, Any]]:
    conditions = ["user_id = %s"]
    params: list[Any] = [current_user.id]
    if start_time:
        conditions.append("recorded_at >= %s")
        params.append(start_time)
    if end_time:
        conditions.append("recorded_at <= %s")
        params.append(end_time)
    params.append(max(1, min(limit, 1000)))
    conn = _create_db_connection()
    try:
        rows = conn.execute(
            f"""SELECT voltage, current, power, energy, channels, recorded_at AS timestamp
                FROM energy_readings WHERE {' AND '.join(conditions)}
                ORDER BY recorded_at DESC, id DESC LIMIT %s""", params,
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


@app.post("/energy/readings")
async def create_energy_reading(payload: EnergyReadingRequest,
                                current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    timestamp = payload.timestamp or datetime.now(timezone.utc)
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """INSERT INTO energy_readings (user_id, voltage, current, power, energy, channels, recorded_at)
               VALUES (%s, %s, %s, %s, %s, %s, %s)
               RETURNING voltage, current, power, energy, channels, recorded_at AS timestamp""",
            (current_user.id, payload.voltage, payload.current, payload.power,
             payload.energy, Jsonb(payload.channels), timestamp),
        ).fetchone()
        device = conn.execute(
            """SELECT id FROM devices WHERE user_id = %s AND lower(name) = 'energy monitor'
               ORDER BY id LIMIT 1""", (current_user.id,),
        ).fetchone()
        device_id = str(device["id"]) if device else None
        pending_pushes = []
        if device_id is not None:
            for sensor_type, value, unit in (("voltage", payload.voltage, "V"), ("current", payload.current, "A")):
                conn.execute(
                    """INSERT INTO sensor_readings (user_id, device_id, sensor_type, value, unit)
                       VALUES (%s, %s, %s, %s, %s)""",
                    (current_user.id, device_id, sensor_type, value, unit),
                )
                push = _evaluate_sensor_thresholds(conn, current_user.id, device_id, sensor_type, value)
                if push:
                    pending_pushes.append(push)
        conn.commit()
        result = dict(row)
    finally:
        conn.close()
    for push in pending_pushes:
        await asyncio.to_thread(_send_push_notification, current_user.id,
                                push["title"], push["message"], push["metadata"])
    return result


@app.post("/sensors/create")
@app.post("/sensors/data")
async def create_sensor_reading(payload: SensorReadingRequest,
                                current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    kind = payload.sensor_type.strip().lower()
    if not kind:
        raise HTTPException(status_code=400, detail="Sensor type is required")
    conn = _create_db_connection()
    pending_push = None
    try:
        device_id = _owned_device_id(conn, current_user.id, payload.device_id)
        row = conn.execute(
            """INSERT INTO sensor_readings (user_id, device_id, sensor_type, value, unit, quality)
               VALUES (%s, %s, %s, %s, %s, %s) RETURNING *""",
            (current_user.id, device_id, kind, payload.value, payload.unit, payload.quality),
        ).fetchone()
        pending_push = _evaluate_sensor_thresholds(conn, current_user.id, device_id, kind, payload.value)
        conn.commit()
        result = _sensor_json(row)
        # The legacy AuthService expects a status message, while SensorService
        # parses the reading fields. Returning both keeps the shared route
        # compatible with both callers.
        result.update({"success": True, "message": "Sensor reading stored"})
    finally:
        conn.close()
    if pending_push:
        await asyncio.to_thread(_send_push_notification, current_user.id,
                                pending_push["title"], pending_push["message"], pending_push["metadata"])
    return result


@app.get("/sensors/device/{device_id}/latest")
async def get_latest_sensor_reading(device_id: str,
                                    current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        canonical_id = _owned_device_id(conn, current_user.id, device_id)
        row = conn.execute(
            """SELECT * FROM sensor_readings WHERE user_id = %s AND device_id = %s
               ORDER BY recorded_at DESC, id DESC LIMIT 1""", (current_user.id, canonical_id),
        ).fetchone()
        return _sensor_json(row) if row else {}
    finally:
        conn.close()


@app.get("/sensors/device/{device_id}")
async def get_device_sensor_readings(device_id: str, sensor_type: str | None = None,
                                     start_time: datetime | None = None,
                                     end_time: datetime | None = None, limit: int = 100,
                                     current_user: UserOut = Depends(get_current_user)) -> list[dict[str, Any]]:
    conn = _create_db_connection()
    try:
        canonical_id = _owned_device_id(conn, current_user.id, device_id)
        conditions = ["user_id = %s", "device_id = %s"]
        params: list[Any] = [current_user.id, canonical_id]
        if sensor_type:
            conditions.append("sensor_type = %s")
            params.append(sensor_type.strip().lower())
        if start_time:
            conditions.append("recorded_at >= %s")
            params.append(start_time)
        if end_time:
            conditions.append("recorded_at <= %s")
            params.append(end_time)
        params.append(max(1, min(limit, 1000)))
        rows = conn.execute(
            f"""SELECT * FROM sensor_readings WHERE {' AND '.join(conditions)}
                ORDER BY recorded_at DESC, id DESC LIMIT %s""", params,
        ).fetchall()
        return [_sensor_json(row) for row in rows]
    finally:
        conn.close()


@app.get("/sensors/all")
async def get_all_sensor_readings(limit: int = 50,
                                 current_user: UserOut = Depends(get_current_user)) -> list[dict[str, Any]]:
    conn = _create_db_connection()
    try:
        rows = conn.execute(
            """SELECT * FROM sensor_readings WHERE user_id = %s
               ORDER BY recorded_at DESC, id DESC LIMIT %s""",
            (current_user.id, max(1, min(limit, 1000))),
        ).fetchall()
        return [_sensor_json(row) for row in rows]
    finally:
        conn.close()


@app.get("/sensors/statistics/{device_id}")
async def get_sensor_statistics(device_id: str, sensor_type: str | None = None,
                                days_back: int = 7,
                                current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        canonical_id = _owned_device_id(conn, current_user.id, device_id)
        params: list[Any] = [current_user.id, canonical_id, max(1, min(days_back, 3650))]
        condition = ""
        if sensor_type:
            condition = " AND sensor_type = %s"
            params.append(sensor_type.strip().lower())
        row = conn.execute(
            f"""SELECT MIN(value) AS min, MAX(value) AS max, AVG(value) AS average,
                       COUNT(*) AS reading_count, MIN(recorded_at) AS start_time,
                       MAX(recorded_at) AS end_time
                FROM sensor_readings WHERE user_id = %s AND device_id = %s
                  AND recorded_at >= CURRENT_TIMESTAMP - (%s * INTERVAL '1 day'){condition}""", params,
        ).fetchone()
        now = datetime.now(timezone.utc)
        return {key: (value if value is not None else 0) for key, value in {
            "min": row["min"], "max": row["max"], "average": row["average"],
            "reading_count": row["reading_count"],
            "start_time": row["start_time"] or now, "end_time": row["end_time"] or now,
        }.items()}
    finally:
        conn.close()


@app.get("/sensors/summary")
async def get_sensor_summary(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """SELECT COUNT(*) AS total_readings,
                       COUNT(DISTINCT sensor_type) AS active_sensors,
                       COUNT(*) FILTER (WHERE recorded_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours') AS readings_24h,
                       MAX(recorded_at) AS last_reading_at
               FROM sensor_readings WHERE user_id = %s""", (current_user.id,),
        ).fetchone()
        return dict(row)
    finally:
        conn.close()


@app.get("/settings/sensor-thresholds")
async def get_sensor_thresholds(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """SELECT voltage_min, voltage_max, amperage_max, sensor_thresholds_configured
               FROM user_preferences WHERE user_id = %s""", (current_user.id,),
        ).fetchone()
        if row is None:
            return {"voltage_min": 200, "voltage_max": 240, "amperage_max": 30, "configured": False}
        return {"voltage_min": row["voltage_min"], "voltage_max": row["voltage_max"],
                "amperage_max": row["amperage_max"], "configured": bool(row["sensor_thresholds_configured"])}
    finally:
        conn.close()


@app.put("/settings/sensor-thresholds")
async def update_sensor_thresholds(payload: SensorThresholdsRequest,
                                   current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    if payload.voltage_min >= payload.voltage_max:
        raise HTTPException(status_code=400, detail="Minimum voltage must be lower than maximum voltage")
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """INSERT INTO user_preferences
               (user_id, voltage_min, voltage_max, amperage_max, sensor_thresholds_configured)
               VALUES (%s, %s, %s, %s, TRUE)
               ON CONFLICT (user_id) DO UPDATE SET voltage_min = EXCLUDED.voltage_min,
                   voltage_max = EXCLUDED.voltage_max, amperage_max = EXCLUDED.amperage_max,
                   sensor_thresholds_configured = TRUE
               RETURNING voltage_min, voltage_max, amperage_max, sensor_thresholds_configured""",
            (current_user.id, payload.voltage_min, payload.voltage_max, payload.amperage_max),
        ).fetchone()
        conn.commit()
        return {"voltage_min": row["voltage_min"], "voltage_max": row["voltage_max"],
                "amperage_max": row["amperage_max"], "configured": bool(row["sensor_thresholds_configured"])}
    finally:
        conn.close()


@app.post("/alerts/create")
async def create_alert(payload: AlertCreateRequest,
                       current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    severity = payload.severity.strip().lower()
    if severity not in {"low", "medium", "high", "critical"}:
        raise HTTPException(status_code=400, detail="Invalid alert severity")
    conn = _create_db_connection()
    try:
        device_id = _owned_device_id(conn, current_user.id, payload.device_id) if payload.device_id else None
        row = _insert_alert(conn, current_user.id, title=payload.title, message=payload.message,
                            severity=severity, source=payload.source.strip().lower() or "system",
                            device_id=device_id, metadata={})
        _insert_alert_notification(conn, current_user.id, row)
        conn.commit()
    finally:
        conn.close()
    metadata = {"alert_id": str(row["id"]), "severity": severity, "source": row["source"]}
    await asyncio.to_thread(_send_push_notification, current_user.id, row["title"], row["message"], metadata)
    return _alert_json(row)


def _alert_filters(user_id: int, *, resolved: bool | None, severity: str | None,
                   device_id: str | None, hours: int | None, unread_only: bool = False) -> tuple[str, list[Any]]:
    conditions = ["user_id = %s"]
    params: list[Any] = [user_id]
    if resolved is not None:
        conditions.append("resolved = %s")
        params.append(resolved)
    if severity:
        conditions.append("severity = %s")
        params.append(severity.strip().lower())
    if device_id:
        conditions.append("device_id = %s")
        params.append(device_id)
    if hours is not None:
        conditions.append("created_at >= CURRENT_TIMESTAMP - (%s * INTERVAL '1 hour')")
        params.append(max(1, min(hours, 24 * 3650)))
    if unread_only:
        conditions.append("is_read = FALSE")
    return " AND ".join(conditions), params


@app.get("/alerts/list")
async def list_alerts(limit: int = 50, offset: int = 0, severity: str | None = None,
                     unread_only: bool = False, resolved: bool | None = None,
                     device_id: str | None = None, hours: int | None = None,
                     current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    where, params = _alert_filters(current_user.id, resolved=resolved, severity=severity,
                                   device_id=device_id, hours=hours, unread_only=unread_only)
    params += [max(1, min(limit, 500)), max(0, offset)]
    conn = _create_db_connection()
    try:
        rows = conn.execute(
            f"""SELECT * FROM alerts WHERE {where} ORDER BY created_at DESC, id DESC
                LIMIT %s OFFSET %s""", params,
        ).fetchall()
        total = conn.execute(f"SELECT COUNT(*) AS count FROM alerts WHERE {where}", params[:-2]).fetchone()["count"]
        return {"alerts": [_alert_json(row) for row in rows], "total": total}
    finally:
        conn.close()


@app.get("/alerts/unread")
async def list_unread_alerts(current_user: UserOut = Depends(get_current_user)) -> list[dict[str, Any]]:
    where, params = _alert_filters(current_user.id, resolved=False, severity=None,
                                   device_id=None, hours=None, unread_only=True)
    conn = _create_db_connection()
    try:
        rows = conn.execute(
            f"SELECT * FROM alerts WHERE {where} ORDER BY created_at DESC, id DESC LIMIT 500", params,
        ).fetchall()
        return [_alert_json(row) for row in rows]
    finally:
        conn.close()


@app.get("/alerts/summary")
async def get_alerts_summary(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """SELECT COUNT(*) AS total_alerts,
                       COUNT(*) FILTER (WHERE resolved = FALSE) AS unresolved_alerts,
                       COUNT(*) FILTER (WHERE is_read = FALSE) AS unread_alerts,
                       COUNT(*) FILTER (WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours') AS alerts_24h
               FROM alerts WHERE user_id = %s""", (current_user.id,),
        ).fetchone()
        return dict(row)
    finally:
        conn.close()


@app.get("/alerts/statistics")
async def get_alert_statistics(days_back: int = 30,
                               current_user: UserOut = Depends(get_current_user)) -> dict[str, int]:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """SELECT COUNT(*) AS total,
                 COUNT(*) FILTER (WHERE is_read = FALSE) AS unread,
                 COUNT(*) FILTER (WHERE severity = 'critical') AS critical,
                 COUNT(*) FILTER (WHERE severity = 'high') AS high,
                 COUNT(*) FILTER (WHERE severity = 'medium') AS medium,
                 COUNT(*) FILTER (WHERE severity = 'low') AS low
               FROM alerts WHERE user_id = %s AND created_at >= CURRENT_TIMESTAMP - (%s * INTERVAL '1 day')""",
            (current_user.id, max(1, min(days_back, 3650))),
        ).fetchone()
        return {key: int(value) for key, value in row.items()}
    finally:
        conn.close()


def _update_alert(current_user_id: int, alert_id: int, *, resolved: bool | None = None,
                  mark_read: bool = False) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        row = conn.execute(
            """UPDATE alerts SET is_read = (is_read OR %s),
                 resolved = COALESCE(%s, resolved)
               WHERE id = %s AND user_id = %s RETURNING *""",
            (mark_read, resolved, alert_id, current_user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Alert not found")
        conn.commit()
        return _alert_json(row)
    finally:
        conn.close()


@app.patch("/alerts/{alert_id}/read")
async def mark_alert_read(alert_id: int,
                          current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    return _update_alert(current_user.id, alert_id, mark_read=True)


@app.patch("/alerts/{alert_id}/dismiss")
async def dismiss_alert(alert_id: int,
                        current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    return _update_alert(current_user.id, alert_id, resolved=True, mark_read=True)


@app.post("/alerts/resolve/{alert_id}")
async def resolve_alert_legacy(alert_id: int,
                               current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    _update_alert(current_user.id, alert_id, resolved=True, mark_read=True)
    return {"success": True}


@app.post("/alerts/mark-all-read")
async def mark_all_alerts_read(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        cursor = conn.execute("UPDATE alerts SET is_read = TRUE WHERE user_id = %s AND is_read = FALSE", (current_user.id,))
        conn.commit()
        return {"success": True, "updated": cursor.rowcount}
    finally:
        conn.close()


@app.post("/alerts/clear-all")
async def clear_all_alerts(current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        cursor = conn.execute("UPDATE alerts SET resolved = TRUE, is_read = TRUE WHERE user_id = %s AND resolved = FALSE", (current_user.id,))
        conn.commit()
        return {"success": True, "deleted": cursor.rowcount, "cleared_count": cursor.rowcount}
    finally:
        conn.close()


@app.delete("/alerts/clear-old")
async def clear_old_alerts(days_old: int = 30,
                           current_user: UserOut = Depends(get_current_user)) -> dict[str, Any]:
    conn = _create_db_connection()
    try:
        cursor = conn.execute(
            "DELETE FROM alerts WHERE user_id = %s AND resolved = TRUE AND created_at < CURRENT_TIMESTAMP - (%s * INTERVAL '1 day')",
            (current_user.id, max(1, days_old)),
        )
        conn.commit()
        return {"success": True, "deleted": cursor.rowcount}
    finally:
        conn.close()


# ============================================================
# GET DEVICE STATUS
# ============================================================

@app.get("/devices/{device_id}/status")
async def get_device_status(
    device_id: int,
    current_user: UserOut = Depends(
        get_current_user
    ),
) -> dict[str, Any]:

    conn = _create_db_connection()

    try:

        row = conn.execute(
            """
            SELECT
                status,
                is_online
            FROM devices
            WHERE id = %s
              AND user_id = %s
            """,
            (
                device_id,
                current_user.id,
            ),
        ).fetchone()

        if row is None:
            raise HTTPException(
                status_code=404,
                detail="Device not found",
            )

        return {
            "status": row["status"],
            "is_online": bool(
                row["is_online"]
            ),
        }

    finally:
        conn.close()


# ============================================================
# RUN SERVER
# ============================================================

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
    )
