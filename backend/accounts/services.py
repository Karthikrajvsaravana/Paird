import logging
import secrets
import uuid
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password, make_password
from django.core.mail import EmailMultiAlternatives
from django.utils.html import escape
from django.db import transaction
from django.utils import timezone
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken

from .identifiers import EMAIL
from .models import AccountIdentity, PasswordResetCode

User = get_user_model()
logger = logging.getLogger(__name__)

RESET_CODE_TTL = timedelta(minutes=15)
RESET_MAX_ATTEMPTS = 5
# A new reset code is emailed at most once per minute per account, so the
# "Resend code" button cannot be used to flood someone's inbox.
RESET_RESEND_COOLDOWN = timedelta(seconds=60)


def _branded_html(paragraphs, footnote=""):
    """Paird-styled HTML email body. `paragraphs` are trusted HTML snippets."""
    body = "".join(f"<p>{paragraph}</p>" for paragraph in paragraphs)
    note = f'<p style="color:#9CA3AF;font-size:13px">{footnote}</p>' if footnote else ""
    return (
        '<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;'
        'background:#121816;color:#F5F5F0;padding:32px;border-radius:12px">'
        '<h1 style="font-family:Georgia,serif;color:#E2C078;font-weight:normal;margin:0 0 24px">Paird</h1>'
        f'{body}{note}<p style="color:#9CA3AF">— The Paird team</p></div>'
    )


def _send_email(to, subject, text, html, purpose):
    """Send one email; log and return False on failure instead of raising."""
    message = EmailMultiAlternatives(subject=subject, body=text, from_email=settings.DEFAULT_FROM_EMAIL, to=[to])
    message.attach_alternative(html, "text/html")
    try:
        message.send()
    except Exception:  # noqa: BLE001 - email problems must not break account flows
        logger.exception("Could not send %s email", purpose)
        return False
    return True


def _support_contact():
    support = settings.PAIRD["SUPPORT_EMAIL"]
    return f"contact us at {support}" if support else "reply to this email"


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
    if kind == EMAIL and settings.PAIRD["WELCOME_EMAIL_ENABLED"]:
        # Only after the account is committed: never welcome an account that
        # was rolled back.
        transaction.on_commit(lambda: send_welcome_email(user.pk))
    return user


def send_welcome_email(user_id):
    """
    Tell a new member their Paird account was created. Best effort: a mail
    failure is logged and never undoes or fails the registration.
    """
    identity = AccountIdentity.objects.filter(user_id=user_id).first()
    if identity is None or not identity.email:
        return False
    if not email_delivery_configured():
        logger.info("Welcome email skipped: email delivery is not configured.")
        return False
    first_name = (identity.full_name.split() or ["there"])[0]
    contact = f"please {_support_contact()}"
    text = (
        f"Hi {first_name},\n\n"
        "Welcome to Paird! Your account has been created.\n\n"
        "Next, complete your profile in the app so others can discover you, "
        "and set your partner preferences.\n\n"
        f"If you didn't create this account, {contact} so we can secure it.\n\n"
        "— The Paird team"
    )
    html = _branded_html(
        [
            f"Hi {escape(first_name)},",
            "<strong>Welcome to Paird!</strong> Your account has been created.",
            "Next, complete your profile in the app so others can discover you, and set your partner preferences.",
        ],
        footnote=f"If you didn't create this account, {escape(contact)} so we can secure it.",
    )
    return _send_email(identity.email, "Welcome to Paird — your account is ready", text, html, "welcome")


def issue_tokens(user):
    refresh = RefreshToken.for_user(user)
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def revoke_all_tokens(user):
    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)


def email_delivery_configured():
    return bool(settings.EMAIL_HOST) or settings.EMAIL_BACKEND != "django.core.mail.backends.smtp.EmailBackend"


def start_password_reset(identity):
    """
    Email a new 6-digit code (replacing any earlier one). Within the resend
    cooldown nothing is sent, so repeated requests cannot flood an inbox.
    Returns True if an email was sent.
    """
    now = timezone.now()
    latest = PasswordResetCode.objects.filter(user=identity.user).order_by("-created_at").first()
    if latest is not None and latest.used_at is None and latest.created_at > now - RESET_RESEND_COOLDOWN:
        return False

    code = f"{secrets.randbelow(1_000_000):06d}"
    with transaction.atomic():
        PasswordResetCode.objects.filter(user=identity.user, used_at__isnull=True).update(used_at=now)
        PasswordResetCode.objects.create(user=identity.user, code_hash=make_password(code), expires_at=now + RESET_CODE_TTL)

    minutes = int(RESET_CODE_TTL.total_seconds() // 60)
    text = (
        f"Your Paird password reset code is {code}.\n\n"
        f"Enter it in the app to choose a new password. It expires in {minutes} minutes and can only be used once.\n\n"
        "If you didn't ask to reset your password, you can ignore this email — your password won't change.\n\n"
        "— The Paird team"
    )
    html = _branded_html(
        [
            "Your password reset code is:",
            f'<span style="font-size:32px;letter-spacing:8px;color:#E2C078;font-weight:bold">{code}</span>',
            f"Enter it in the app to choose a new password. It expires in {minutes} minutes and can only be used once.",
        ],
        footnote="If you didn't ask to reset your password, you can ignore this email — your password won't change.",
    )
    return _send_email(identity.email, "Your Paird password reset code", text, html, "password reset")


def send_password_changed_email(user_id):
    """Security notice after a password reset or change."""
    identity = AccountIdentity.objects.filter(user_id=user_id).first()
    if identity is None or not identity.email or not email_delivery_configured():
        return False
    first_name = (identity.full_name.split() or ["there"])[0]
    when = timezone.now().strftime("%d %b %Y, %H:%M UTC")
    contact = _support_contact()
    text = (
        f"Hi {first_name},\n\n"
        f"The password for your Paird account was changed on {when}. "
        "For your security, you've been signed out on your other devices.\n\n"
        f"If this wasn't you, reset your password from the app right away and {contact}.\n\n"
        "— The Paird team"
    )
    html = _branded_html(
        [
            f"Hi {escape(first_name)},",
            f"The password for your Paird account was changed on <strong>{when}</strong>.",
            "For your security, you've been signed out on your other devices.",
        ],
        footnote=f"If this wasn't you, reset your password from the app right away and {escape(contact)}.",
    )
    return _send_email(identity.email, "Your Paird password was changed", text, html, "password changed")


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
    transaction.on_commit(lambda: send_password_changed_email(user.pk))
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
            logger.warning("Could not delete stored file for removed account")
