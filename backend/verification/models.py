import uuid

from django.conf import settings
from django.db import models
from django.db.models import Q


def selfie_upload_path(instance, filename):
    return f"verification/{instance.user_id}/{uuid.uuid4().hex}.jpg"


class VerificationRequest(models.Model):
    """
    Photo verification by manual review: the member submits a live selfie and
    Paird staff compare it with the member's profile photos in the Django admin.
    This is NOT identity-document verification. The selfie is deleted as soon
    as a decision is recorded.
    """

    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    STATUSES = [(PENDING, "Pending review"), (APPROVED, "Approved"), (REJECTED, "Rejected")]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="verification_requests")
    selfie = models.ImageField(upload_to=selfie_upload_path, null=True, blank=True)
    status = models.CharField(max_length=10, choices=STATUSES, default=PENDING)
    rejection_reason = models.CharField(max_length=200, blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="+"
    )

    class Meta:
        ordering = ["-submitted_at"]
        constraints = [
            models.UniqueConstraint(fields=["user"], condition=Q(status="pending"), name="one_pending_verification"),
        ]
