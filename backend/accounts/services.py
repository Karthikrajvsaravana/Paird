import secrets
import uuid
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password, make_password
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken

from .identifiers import EMAIL
from .models import AccountIdentity, PasswordResetCode

User = get_user_model()

RESET_CODE_TTL = timedelta(minutes=15)
RESET_MAX_ATTEMPTS = 5


@transaction.atomic
def create_account(full_name, kind, identifier, password):
    from profiles.services import get_preference, get_profile

    user = User(username=f"u_{uuid.uuid4().hex[:24]}", first_name=full_name[:150])
    if kind == EMAIL:
        user.email = identifier
    user.set_password(password)
    user.save()
    AccountIdentity.objects.create(
        user=user,
        full_name=full_name,
        email=identifier if kind == EMAIL else None,
        phone=None if kind == EMAIL else identifier,
    )
    get_profile(user)
    get_preference(user)
    return user


def issue_tokens(user):
    refresh = RefreshToken.for_user(user)
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def revoke_all_tokens(user):
    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)


def email_delivery_configured():
    return bool(settings.EMAIL_HOST) or settings.EMAIL_BACKEND != "django.core.mail.backends.smtp.EmailBackend"


def start_password_reset(identity):
    code = f"{secrets.randbelow(1_000_000):06d}"
    PasswordResetCode.objects.filter(user=identity.user, used_at__isnull=True).update(used_at=timezone.now())
    PasswordResetCode.objects.create(
        user=identity.user, code_hash=make_password(code), expires_at=timezone.now() + RESET_CODE_TTL
    )
    send_mail(
        subject="Your Paird password reset code",
        message=(
            f"Your Paird password reset code is {code}.\n\n"
            "It expires in 15 minutes. If you didn't ask to reset your password, you can ignore this email."
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[identity.email],
    )


@transaction.atomic
def confirm_password_reset(user, code, new_password):
    """Returns True if the code was valid and the password was changed."""
    reset = (
        PasswordResetCode.objects.select_for_update()
        .filter(user=user, used_at__isnull=True, expires_at__gt=timezone.now())
        .order_by("-created_at")
        .first()
    )
    if reset is None or reset.attempts >= RESET_MAX_ATTEMPTS:
        return False
    if not check_password(code, reset.code_hash):
        reset.attempts += 1
        reset.save(update_fields=["attempts"])
        return False
    reset.used_at = timezone.now()
    reset.save(update_fields=["used_at"])
    user.set_password(new_password)
    user.save(update_fields=["password"])
    revoke_all_tokens(user)
    return True


def delete_account(user):
    """Permanently delete the member and their data, including stored files."""
    from profiles.services import delete_stored_file
    from verification.models import VerificationRequest

    files = [photo.image for photo in user.photos.all()]
    files += [req.selfie for req in VerificationRequest.objects.filter(user=user)]
    with transaction.atomic():
        revoke_all_tokens(user)
        user.delete()
    for field_file in files:
        try:
            delete_stored_file(field_file)
        except Exception:  # noqa: BLE001 - account is already gone; log-and-continue
            import logging

            logging.getLogger(__name__).warning("Could not delete stored file for removed account")
