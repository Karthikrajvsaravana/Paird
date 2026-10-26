from django.conf import settings
from django.db import models
from django.db.models import F, Q
from django.utils import timezone


class InterestQuerySet(models.QuerySet):
    def expire_due(self):
        """Persist expiry for pending interests whose window has passed."""
        now = timezone.now()
        return self.filter(status=Interest.PENDING, expires_at__lte=now).update(
            status=Interest.EXPIRED, responded_at=now
        )


class Interest(models.Model):
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    WITHDRAWN = "withdrawn"
    EXPIRED = "expired"
    STATUSES = [
        (PENDING, "Pending"),
        (ACCEPTED, "Accepted"),
        (DECLINED, "Declined"),
        (WITHDRAWN, "Withdrawn"),
        (EXPIRED, "Expired"),
    ]

    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="interests_sent")
    receiver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="interests_received")
    status = models.CharField(max_length=10, choices=STATUSES, default=PENDING)
    note = models.CharField(max_length=300, blank=True)
    created_at = models.DateTimeField(default=timezone.now)
    expires_at = models.DateTimeField()
    responded_at = models.DateTimeField(null=True, blank=True)

    objects = InterestQuerySet.as_manager()

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["sender", "receiver"], condition=Q(status="pending"), name="one_pending_interest_per_pair"
            ),
            models.CheckConstraint(condition=~Q(sender=F("receiver")), name="interest_not_self"),
        ]
        indexes = [
            models.Index(fields=["receiver", "status", "-created_at"]),
            models.Index(fields=["sender", "status", "-created_at"]),
            models.Index(fields=["status", "expires_at"]),
        ]

    @property
    def is_effectively_pending(self):
        return self.status == self.PENDING and self.expires_at > timezone.now()


class Match(models.Model):
    """A mutual match. Stored once per pair with user_a_id < user_b_id."""

    user_a = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    user_b = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    interest = models.OneToOneField(Interest, on_delete=models.SET_NULL, null=True, blank=True, related_name="match")
    created_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    ended_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="+"
    )

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["user_a", "user_b"], name="unique_match_pair"),
            models.CheckConstraint(condition=Q(user_a__lt=F("user_b")), name="match_pair_ordered"),
        ]

    @property
    def is_active(self):
        return self.ended_at is None

    def other(self, user):
        return self.user_b if self.user_a_id == user.id else self.user_a

    def other_id(self, user):
        return self.user_b_id if self.user_a_id == user.id else self.user_a_id

    @staticmethod
    def ordered(a_id, b_id):
        return (a_id, b_id) if a_id < b_id else (b_id, a_id)
