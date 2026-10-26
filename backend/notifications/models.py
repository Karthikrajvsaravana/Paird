from django.conf import settings
from django.db import models


class Notification(models.Model):
    INTEREST_RECEIVED = "interest_received"
    INTEREST_ACCEPTED = "interest_accepted"
    NEW_MATCH = "new_match"
    VERIFICATION_UPDATED = "verification_updated"
    KINDS = [
        (INTEREST_RECEIVED, "Interest received"),
        (INTEREST_ACCEPTED, "Interest accepted"),
        (NEW_MATCH, "New match"),
        (VERIFICATION_UPDATED, "Verification updated"),
    ]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    kind = models.CharField(max_length=30, choices=KINDS)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True, related_name="+"
    )
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=300, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "read_at", "-created_at"])]


class NotificationPreference(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notification_preference")
    interests = models.BooleanField(default=True)
    matches = models.BooleanField(default=True)
    messages = models.BooleanField(default=True)
    account = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)
