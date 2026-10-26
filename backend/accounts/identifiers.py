"""Normalisation of the single "email or phone number" sign-in identifier."""

import re

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import validate_email

EMAIL = "email"
PHONE = "phone"

_PHONE_STRIP = re.compile(r"[\s\-().]")
_E164 = re.compile(r"^\+[1-9]\d{7,14}$")

INVALID_MESSAGE = "Enter a valid email address or a phone number with country code (for example +919876543210)."


def normalize_identifier(raw):
    """Return (kind, normalized_value) or raise ValidationError."""
    value = (raw or "").strip()
    if not value:
        raise ValidationError("Enter your email or phone number.")
    if "@" in value:
        value = value.lower()
        if len(value) > 254:
            raise ValidationError(INVALID_MESSAGE)
        try:
            validate_email(value)
        except ValidationError:
            raise ValidationError(INVALID_MESSAGE) from None
        return EMAIL, value

    phone = _PHONE_STRIP.sub("", value)
    if phone.startswith("00"):
        phone = "+" + phone[2:]
    if not phone.startswith("+"):
        default_code = settings.PAIRD["DEFAULT_PHONE_COUNTRY_CODE"]
        if default_code and phone.isdigit():
            phone = default_code + phone.lstrip("0")
    if not _E164.match(phone):
        raise ValidationError(INVALID_MESSAGE)
    return PHONE, phone
