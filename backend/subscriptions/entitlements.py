"""
Single source of truth for Premium plans and entitlements. The Flutter app
renders whatever this module returns; it never decides entitlements itself.
"""

from django.conf import settings
from django.utils import timezone

from .models import Subscription

PLANS = [
    {
        "id": "free",
        "name": "Paird Free",
        "features": [
            "Create a full profile and partner preferences",
            "Discover profiles and see Vibe Scores",
            "{limit} interests per day",
            "Message your mutual matches",
        ],
    },
    {
        "id": "premium",
        "name": "Paird Premium",
        "features": [
            "Unlimited interests",
            "Everything in Free",
        ],
    },
]


def active_subscription(user):
    now = timezone.now()
    return (
        Subscription.objects.filter(user=user, status="active", starts_at__lte=now, expires_at__gt=now)
        .order_by("-expires_at")
        .first()
    )


def entitlements_for(user):
    subscription = active_subscription(user)
    premium = subscription is not None
    return {
        "plan": "premium" if premium else "free",
        "is_premium": premium,
        "expires_at": subscription.expires_at if subscription else None,
        "daily_interest_limit": None if premium else settings.PAIRD["FREE_DAILY_INTEREST_LIMIT"],
    }


def plans():
    limit = settings.PAIRD["FREE_DAILY_INTEREST_LIMIT"]
    return [
        {**plan, "features": [feature.format(limit=limit) for feature in plan["features"]]} for plan in PLANS
    ]
