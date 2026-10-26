from django.conf import settings
from django.db import models
from django.utils import timezone


class Subscription(models.Model):
    """
    Server-side record of a Premium entitlement. Rows are created only by a
    verified payment provider webhook (not yet configured) or by staff in the
    Django admin (e.g. complimentary access). Clients can never create them.
    """

    SOURCES = [("admin", "Granted by staff"), ("google_play", "Google Play"), ("stripe", "Stripe")]
    STATUSES = [("active", "Active"), ("cancelled", "Cancelled"), ("expired", "Expired")]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="subscriptions")
    plan = models.CharField(max_length=20, default="premium")
    status = models.CharField(max_length=10, choices=STATUSES, default="active")
    source = models.CharField(max_length=20, choices=SOURCES, default="admin")
    external_reference = models.CharField(max_length=200, blank=True)
    starts_at = models.DateTimeField(default=timezone.now)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-expires_at"]
        indexes = [models.Index(fields=["user", "status", "expires_at"])]
