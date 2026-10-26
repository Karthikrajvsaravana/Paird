"""
Django settings for the Paird backend.

All secrets and environment-specific values are read from environment
variables (loaded from backend/.env in development). See backend/.env.example
for the full list.
"""

import os
from datetime import timedelta
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(BASE_DIR / ".env")


def env_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_list(name, default=""):
    return [item.strip() for item in os.environ.get(name, default).split(",") if item.strip()]


def env_int(name, default):
    value = os.environ.get(name)
    return int(value) if value not in (None, "") else default


def require_env(name):
    value = os.environ.get(name)
    if not value:
        raise ImproperlyConfigured(f"The {name} environment variable is required.")
    return value


# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = require_env("DJANGO_SECRET_KEY")

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = env_bool("DJANGO_DEBUG", False)

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")


# Application definition

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    # Third party
    'rest_framework',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    # Paird
    'core',
    'accounts',
    'profiles',
    'safety',
    'matching',
    'messaging',
    'notifications',
    'verification',
    'subscriptions',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'


# Database
# https://docs.djangoproject.com/en/5.2/ref/settings/#databases

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": require_env("DB_NAME"),
        "USER": require_env("DB_USER"),
        "PASSWORD": require_env("DB_PASSWORD"),
        "HOST": require_env("DB_HOST"),
        "PORT": os.environ.get("DB_PORT", "5432"),
        "OPTIONS": {
            "sslmode": os.environ.get("DB_SSLMODE", "require"),
        },
        "CONN_MAX_AGE": env_int("DB_CONN_MAX_AGE", 60),
        # Supabase's transaction pooler (port 6543) does not support
        # server-side cursors. Harmless with the session pooler.
        "DISABLE_SERVER_SIDE_CURSORS": env_bool("DB_DISABLE_SERVER_SIDE_CURSORS", True),
    }
}

AUTHENTICATION_BACKENDS = [
    'accounts.backends.EmailOrPhoneBackend',
    'django.contrib.auth.backends.ModelBackend',
]

# Password validation
# https://docs.djangoproject.com/en/5.2/ref/settings/#auth-password-validators

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]


# Internationalization
# https://docs.djangoproject.com/en/5.2/topics/i18n/

LANGUAGE_CODE = 'en-us'

TIME_ZONE = 'UTC'

USE_I18N = True

USE_TZ = True


# Static files (CSS, JavaScript, Images)
# https://docs.djangoproject.com/en/5.2/howto/static-files/

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

# Uploaded files (profile photos, verification selfies). These are never
# served publicly: the API streams them after an authorization check.
MEDIA_ROOT = Path(os.environ.get("MEDIA_ROOT", BASE_DIR / "media"))

STORAGE_BACKEND = os.environ.get("STORAGE_BACKEND", "filesystem").strip().lower()
if STORAGE_BACKEND == "s3":
    # S3-compatible object storage (e.g. Supabase Storage's S3 endpoint).
    # Requires `pip install django-storages[s3]`. Use a PRIVATE bucket.
    STORAGES = {
        "default": {
            "BACKEND": "storages.backends.s3.S3Storage",
            "OPTIONS": {
                "bucket_name": require_env("STORAGE_S3_BUCKET"),
                "endpoint_url": require_env("STORAGE_S3_ENDPOINT_URL"),
                "region_name": os.environ.get("STORAGE_S3_REGION", ""),
                "access_key": require_env("STORAGE_S3_ACCESS_KEY_ID"),
                "secret_key": require_env("STORAGE_S3_SECRET_ACCESS_KEY"),
                "default_acl": None,
                "querystring_auth": True,
                "querystring_expire": 300,
                "file_overwrite": False,
            },
        },
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
elif STORAGE_BACKEND != "filesystem":
    raise ImproperlyConfigured("STORAGE_BACKEND must be 'filesystem' or 's3'.")

# Upload limits (bytes)
PHOTO_MAX_UPLOAD_BYTES = env_int("PHOTO_MAX_UPLOAD_BYTES", 5 * 1024 * 1024)
PHOTO_MAX_PER_PROFILE = env_int("PHOTO_MAX_PER_PROFILE", 6)
DATA_UPLOAD_MAX_MEMORY_SIZE = 2 * 1024 * 1024
FILE_UPLOAD_MAX_MEMORY_SIZE = 2 * 1024 * 1024

# Default primary key field type
# https://docs.djangoproject.com/en/5.2/ref/settings/#default-auto-field

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'


# Django REST Framework

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "core.authentication.ActivityTrackingJWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
    ],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
        "rest_framework.parsers.MultiPartParser",
    ],
    "EXCEPTION_HANDLER": "core.exceptions.api_exception_handler",
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.UserRateThrottle",
        "rest_framework.throttling.AnonRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "user": os.environ.get("THROTTLE_USER", "600/min"),
        "anon": os.environ.get("THROTTLE_ANON", "60/min"),
        "auth": os.environ.get("THROTTLE_AUTH", "10/min"),
        "interests": os.environ.get("THROTTLE_INTERESTS", "30/min"),
        "messages": os.environ.get("THROTTLE_MESSAGES", "60/min"),
        "reports": os.environ.get("THROTTLE_REPORTS", "10/hour"),
        "uploads": os.environ.get("THROTTLE_UPLOADS", "20/hour"),
    },
}

if DEBUG:
    REST_FRAMEWORK["DEFAULT_RENDERER_CLASSES"].append("rest_framework.renderers.BrowsableAPIRenderer")

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env_int("JWT_ACCESS_MINUTES", 15)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env_int("JWT_REFRESH_DAYS", 30)),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": True,
    "SIGNING_KEY": os.environ.get("JWT_SIGNING_KEY") or SECRET_KEY,
    "AUTH_HEADER_TYPES": ("Bearer",),
}

# Mobile apps do not need CORS. Only list browser origins that genuinely
# call the API (e.g. a Flutter web build). Never use allow-all.
CORS_ALLOWED_ORIGINS = env_list("CORS_ALLOWED_ORIGINS")
CORS_ALLOW_CREDENTIALS = False
CSRF_TRUSTED_ORIGINS = env_list("CSRF_TRUSTED_ORIGINS")

# Caching (used by throttling). Use a shared cache such as Redis when
# running more than one backend process.
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "paird",
    }
}


# Paird product rules (documented in README.md)

PAIRD = {
    "MIN_AGE": env_int("PAIRD_MIN_AGE", 18),
    "MAX_AGE": 100,
    "INTEREST_EXPIRY_DAYS": env_int("PAIRD_INTEREST_EXPIRY_DAYS", 7),
    "DECLINE_COOLDOWN_DAYS": env_int("PAIRD_DECLINE_COOLDOWN_DAYS", 30),
    "FREE_DAILY_INTEREST_LIMIT": env_int("PAIRD_FREE_DAILY_INTEREST_LIMIT", 10),
    "DISCOVERY_CANDIDATE_CAP": env_int("PAIRD_DISCOVERY_CANDIDATE_CAP", 500),
    "DEFAULT_PHONE_COUNTRY_CODE": os.environ.get("PAIRD_DEFAULT_PHONE_COUNTRY_CODE", "").strip(),
    "MESSAGE_MAX_LENGTH": 2000,
}


# Production security. These activate automatically when DEBUG is off.

if not DEBUG:
    SECURE_PROXY_SSL_HEADER = (
        ("HTTP_X_FORWARDED_PROTO", "https") if env_bool("DJANGO_BEHIND_HTTPS_PROXY", False) else None
    )
    SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", True)
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = env_int("DJANGO_HSTS_SECONDS", 31536000)
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = False
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_REFERRER_POLICY = "same-origin"
    X_FRAME_OPTIONS = "DENY"

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": os.environ.get("DJANGO_LOG_LEVEL", "INFO")},
}


# Email (used for password reset codes). In DEBUG without SMTP settings,
# emails are printed to the console instead of being sent.
EMAIL_HOST = os.environ.get("EMAIL_HOST", "")
EMAIL_PORT = env_int("EMAIL_PORT", 587)
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = env_bool("EMAIL_USE_TLS", True)
DEFAULT_FROM_EMAIL = os.environ.get("DEFAULT_FROM_EMAIL", "Paird <no-reply@localhost>")
EMAIL_BACKEND = os.environ.get(
    "EMAIL_BACKEND",
    "django.core.mail.backends.console.EmailBackend"
    if DEBUG and not EMAIL_HOST
    else "django.core.mail.backends.smtp.EmailBackend",
)
