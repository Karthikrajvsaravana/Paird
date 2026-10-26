from django.conf import settings
from django.db import models
from django.db.models import Q


class AccountIdentity(models.Model):
    """
    Sign-in identity for a user. Extends Django's default auth.User (which the
    existing database already uses) without swapping AUTH_USER_MODEL.

    Exactly one of email/phone is required; both are normalised and unique.
    These values are private and never returned to other users.
    """

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="identity")
    full_name = models.CharField(max_length=150)
    email = models.EmailField(max_length=254, unique=True, null=True, blank=True)
    phone = models.CharField(max_length=16, unique=True, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(email__isnull=False) | Q(phone__isnull=False),
                name="identity_has_email_or_phone",
            ),
        ]

    def __str__(self):
        return f"Identity<{self.user_id}>"

    @property
    def identifier(self):
        return self.email or self.phone


class PasswordResetCode(models.Model):
    """Short-lived, single-use password reset code (stored hashed)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="password_reset_codes")
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    used_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["user", "-created_at"])]
