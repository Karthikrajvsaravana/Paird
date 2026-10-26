from .models import Notification, NotificationPreference

CATEGORY = {
    Notification.INTEREST_RECEIVED: "interests",
    Notification.INTEREST_ACCEPTED: "matches",
    Notification.NEW_MATCH: "matches",
    Notification.VERIFICATION_UPDATED: "account",
}


def get_preferences(user):
    preference, _ = NotificationPreference.objects.get_or_create(user=user)
    return preference


def notify(user, kind, *, title, body="", actor=None):
    """Create an in-app notification if the member has that category enabled."""
    preference = get_preferences(user)
    if not getattr(preference, CATEGORY[kind], True):
        return None
    return Notification.objects.create(user=user, kind=kind, actor=actor, title=title[:120], body=body[:300])
