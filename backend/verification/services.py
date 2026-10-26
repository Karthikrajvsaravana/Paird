from .models import VerificationRequest


def verification_status(user):
    """'unverified' | 'pending' | 'verified' | 'rejected'."""
    latest = VerificationRequest.objects.filter(user=user).order_by("-submitted_at").first()
    if latest is None:
        return "unverified"
    if latest.status == VerificationRequest.APPROVED:
        return "verified"
    if latest.status == VerificationRequest.PENDING:
        # A previous approval still stands while a re-submission is pending.
        if VerificationRequest.objects.filter(user=user, status=VerificationRequest.APPROVED).exists():
            return "verified"
        return "pending"
    return "rejected"


def is_verified(user):
    return VerificationRequest.objects.filter(user=user, status=VerificationRequest.APPROVED).exists()


def verified_user_ids(user_ids):
    return set(
        VerificationRequest.objects.filter(user_id__in=user_ids, status=VerificationRequest.APPROVED).values_list(
            "user_id", flat=True
        )
    )
