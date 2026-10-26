"""
Settings for automated tests. PostgreSQL only — there is no SQLite fallback.

Tests run against a DEDICATED test PostgreSQL server (for example a separate
Supabase project used only for testing), configured with TEST_DB_* variables
in backend/.env or the shell:

    TEST_DB_NAME, TEST_DB_USER, TEST_DB_PASSWORD, TEST_DB_HOST,
    TEST_DB_PORT (default 5432), TEST_DB_SSLMODE (default require)

Django's test runner creates a temporary database named "test_<TEST_DB_NAME>"
on that server and destroys it afterwards. It never touches the application
database configured by DB_*; this module refuses to run if the two point at
the same database.
"""

import os
import tempfile
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

_missing = [name for name in ("TEST_DB_NAME", "TEST_DB_USER", "TEST_DB_PASSWORD", "TEST_DB_HOST") if not os.environ.get(name)]
if _missing:
    raise ImproperlyConfigured(
        "Automated tests need a dedicated PostgreSQL test database. Set these variables "
        f"(see docs/IMPLEMENTATION_STATUS.md, 'Running tests'): {', '.join(_missing)}"
    )

# Tests never need the real secret key.
os.environ.setdefault("DJANGO_SECRET_KEY", "test-only-not-secret")
os.environ["STORAGE_BACKEND"] = "filesystem"
os.environ["MEDIA_ROOT"] = tempfile.mkdtemp(prefix="paird-test-media-")

from .settings import *  # noqa: E402,F401,F403

_test_target = (os.environ["TEST_DB_HOST"].lower(), os.environ.get("TEST_DB_PORT", "5432"), os.environ["TEST_DB_NAME"])
_app_target = (
    os.environ.get("DB_HOST", "").lower(),
    os.environ.get("DB_PORT", "5432"),
    os.environ.get("DB_NAME", ""),
)
if _test_target == _app_target:
    raise ImproperlyConfigured(
        "TEST_DB_* points at the same database as DB_*. Use a separate test project/database "
        "so tests can never touch application data."
    )

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ["TEST_DB_NAME"],
        "USER": os.environ["TEST_DB_USER"],
        "PASSWORD": os.environ["TEST_DB_PASSWORD"],
        "HOST": os.environ["TEST_DB_HOST"],
        "PORT": os.environ.get("TEST_DB_PORT", "5432"),
        "OPTIONS": {"sslmode": os.environ.get("TEST_DB_SSLMODE", "require")},
        "DISABLE_SERVER_SIDE_CURSORS": True,
        "TEST": {"NAME": f"test_{os.environ['TEST_DB_NAME']}"},
    }
}

SECRET_KEY = "test-only-not-secret"
SIMPLE_JWT = {**SIMPLE_JWT, "SIGNING_KEY": SECRET_KEY}  # noqa: F405
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]  # speed only; production uses PBKDF2
DEBUG = False
SECURE_SSL_REDIRECT = False
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
REST_FRAMEWORK = {
    **REST_FRAMEWORK,  # noqa: F405
    "DEFAULT_THROTTLE_RATES": {
        **REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"],  # noqa: F405
        "auth": "1000/min",
        "interests": "1000/min",
        "messages": "1000/min",
        "reports": "1000/min",
        "uploads": "1000/min",
        "anon": "1000/min",
    },
}

# Expected 4xx responses are logged by django.request; keep test output readable.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"null": {"class": "logging.NullHandler"}},
    "loggers": {"django.request": {"handlers": ["null"], "propagate": False}},
}
