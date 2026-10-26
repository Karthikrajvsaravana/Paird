from django.db.models import Q

from .models import Block


def blocked_user_ids(user):
    """IDs of everyone this user has blocked or been blocked by."""
    pairs = Block.objects.filter(Q(blocker=user) | Q(blocked=user)).values_list("blocker_id", "blocked_id")
    ids = set()
    for blocker_id, blocked_id in pairs:
        ids.add(blocked_id if blocker_id == user.id else blocker_id)
    return ids


def is_blocked_between(a, b):
    return Block.objects.filter(Q(blocker=a, blocked=b) | Q(blocker=b, blocked=a)).exists()
