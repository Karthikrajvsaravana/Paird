from django.conf import settings
from django.db import models
from django.db.models import F, Q


class Block(models.Model):
    blocker = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="blocks_made")
    blocked = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="blocks_received")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["blocker", "blocked"], name="unique_block"),
            models.CheckConstraint(condition=~Q(blocker=F("blocked")), name="block_not_self"),
        ]


class Report(models.Model):
    REASONS = [
        ("fake_profile", "Fake or misleading profile"),
        ("inappropriate_photos", "Inappropriate photos"),
        ("harassment", "Harassment or abusive messages"),
        ("scam", "Scam or asking for money"),
        ("underage", "May be under the minimum age"),
        ("already_married", "Appears to be already married"),
        ("other", "Other"),
    ]
    STATUSES = [("open", "Open"), ("reviewing", "Under review"), ("actioned", "Actioned"), ("dismissed", "Dismissed")]

    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="reports_made"
    )
    reported_user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="reports_received")
    reason = models.CharField(max_length=30, choices=REASONS)
    details = models.TextField(max_length=1000, blank=True)
    message = models.ForeignKey("messaging.Message", on_delete=models.SET_NULL, null=True, blank=True)
    status = models.CharField(max_length=12, choices=STATUSES, default="open")
    created_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["status", "created_at"])]
