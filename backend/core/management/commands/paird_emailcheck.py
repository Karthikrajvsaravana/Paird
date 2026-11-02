"""
Show how outgoing email is configured (no secrets) and optionally send a
test email. Also tells you whether an address belongs to a Paird account.

    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_emailcheck
    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_emailcheck --send-to you@example.com
"""

from django.conf import settings
from django.core.mail import send_mail
from django.core.management.base import BaseCommand, CommandError

from accounts.services import email_delivery_configured


def _mask(address):
    if "@" not in address:
        return "(not set)" if not address else "(set)"
    name, domain = address.split("@", 1)
    return f"{name[:2]}…@{domain}"


class Command(BaseCommand):
    help = "Check outgoing email settings and optionally send a test email."

    def add_arguments(self, parser):
        parser.add_argument("--send-to", help="Send a test email to this address.")

    def handle(self, *args, **options):
        backend = settings.EMAIL_BACKEND.rsplit(".", 2)[-2]
        self.stdout.write(f"Email backend:   {backend}")
        if backend == "console":
            self.stdout.write(
                self.style.WARNING(
                    "Emails are PRINTED in the Django server window, not sent. "
                    "Add EMAIL_HOST, EMAIL_HOST_USER and EMAIL_HOST_PASSWORD to backend/.env to send real email."
                )
            )
        elif backend == "smtp":
            self.stdout.write(f"SMTP host:       {settings.EMAIL_HOST or '(not set)'}:{settings.EMAIL_PORT}")
            self.stdout.write(f"TLS:             {'on' if settings.EMAIL_USE_TLS else 'off'}")
            self.stdout.write(f"Login user:      {_mask(settings.EMAIL_HOST_USER)}")
            self.stdout.write(f"Login password:  {'set' if settings.EMAIL_HOST_PASSWORD else 'NOT SET'}")
        self.stdout.write(f"From address:    {settings.DEFAULT_FROM_EMAIL}")
        if backend == "console":
            ready = "NO — console mode only prints emails"
        else:
            ready = "yes" if email_delivery_configured() else "NO — EMAIL_HOST is not set"
        self.stdout.write(f"Real delivery:   {ready}")

        target = options.get("send_to")
        if not target:
            return
        target = target.strip().lower()
        from accounts.models import AccountIdentity

        exists = AccountIdentity.objects.filter(email=target, user__is_active=True).exists()
        self.stdout.write(f"Paird account:   {'found' if exists else 'NOT FOUND — reset codes are only sent to registered emails'}")
        try:
            send_mail(
                "Paird test email",
                "This is a test email from your Paird backend. Email sending works.",
                settings.DEFAULT_FROM_EMAIL,
                [target],
            )
        except Exception as exc:  # noqa: BLE001 - show a helpful message, never the password
            hint = ""
            if "535" in str(exc) or "Username and Password not accepted" in str(exc):
                hint = " Gmail rejected the login: use a 16-character App Password, not your normal password."
            raise CommandError(f"Sending failed ({exc.__class__.__name__}: {str(exc)[:160]}).{hint}") from None
        if backend == "console":
            self.stdout.write(self.style.WARNING("Test email printed above (console mode) — nothing was actually sent."))
        else:
            self.stdout.write(self.style.SUCCESS(f"Test email sent to {_mask(target)}. Check the inbox and spam folder."))
