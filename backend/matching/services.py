from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import exceptions

from core.exceptions import Conflict
from notifications.models import Notification
from notifications.services import notify
from profiles.serializers import display_name
from profiles.services import can_view_profile, get_profile
from safety.services import is_blocked_between
from subscriptions.entitlements import entitlements_for
from verification.services import is_verified

from .models import Interest, Match

User = get_user_model()


def match_between(a_id, b_id):
    low, high = Match.ordered(a_id, b_id)
    return Match.objects.filter(user_a_id=low, user_b_id=high).first()


def active_match_between(a_id, b_id):
    match = match_between(a_id, b_id)
    return match if match and match.is_active else None


def active_match_user_ids(user):
    rows = Match.objects.filter(Q(user_a=user) | Q(user_b=user), ended_at__isnull=True).values_list(
        "user_a_id", "user_b_id"
    )
    return {b if a == user.id else a for a, b in rows}


def _cooldown_start():
    return timezone.now() - timedelta(days=settings.PAIRD["DECLINE_COOLDOWN_DAYS"])


def connection_map(viewer, user_ids):
    """Describe the viewer's connection with each of the given users."""
    from messaging.models import Conversation

    user_ids = set(user_ids)
    result = {uid: {"status": "none", "interest_id": None, "match_id": None, "conversation_id": None} for uid in user_ids}
    if not user_ids:
        return result

    now = timezone.now()
    interests = Interest.objects.filter(
        Q(sender=viewer, receiver_id__in=user_ids) | Q(receiver=viewer, sender_id__in=user_ids)
    ).order_by("created_at")
    cooldown = _cooldown_start()
    for interest in interests:
        other = interest.receiver_id if interest.sender_id == viewer.id else interest.sender_id
        entry = result[other]
        effective_pending = interest.status == Interest.PENDING and interest.expires_at > now
        if effective_pending:
            entry["status"] = "interest_sent" if interest.sender_id == viewer.id else "interest_received"
            entry["interest_id"] = interest.id
            entry["expires_at"] = interest.expires_at
        elif (
            interest.status == Interest.DECLINED
            and interest.sender_id == viewer.id
            and interest.responded_at
            and interest.responded_at > cooldown
        ):
            entry["status"] = "declined"
            entry["interest_id"] = interest.id

    matches = Match.objects.filter(
        Q(user_a=viewer, user_b_id__in=user_ids) | Q(user_b=viewer, user_a_id__in=user_ids), ended_at__isnull=True
    )
    match_ids = {}
    for match in matches:
        other = match.other_id(viewer)
        result[other].update({"status": "matched", "match_id": match.id, "interest_id": None})
        match_ids[match.id] = other
    for conversation in Conversation.objects.filter(match_id__in=match_ids):
        result[match_ids[conversation.match_id]]["conversation_id"] = conversation.id

    for entry in result.values():
        entry["can_send_interest"] = entry["status"] == "none"
    return result


def interests_sent_today(user):
    since = timezone.now() - timedelta(hours=24)
    return Interest.objects.filter(sender=user, created_at__gte=since).count()


@transaction.atomic
def _create_match(interest):
    low, high = Match.ordered(interest.sender_id, interest.receiver_id)
    match, created = Match.objects.select_for_update().get_or_create(
        user_a_id=low, user_b_id=high, defaults={"interest": interest}
    )
    if not created and match.ended_at is not None:
        match.ended_at = None
        match.ended_by = None
        match.interest = interest
        match.save(update_fields=["ended_at", "ended_by", "interest"])
    from messaging.models import Conversation

    Conversation.objects.get_or_create(match=match)
    return match


def _accept(interest):
    now = timezone.now()
    interest.status = Interest.ACCEPTED
    interest.responded_at = now
    interest.save(update_fields=["status", "responded_at"])
    match = _create_match(interest)
    notify(
        interest.sender,
        Notification.INTEREST_ACCEPTED,
        actor=interest.receiver,
        title=f"{display_name(interest.receiver)} accepted your interest",
        body="You're now a match. Say hello!",
    )
    notify(
        interest.receiver,
        Notification.NEW_MATCH,
        actor=interest.sender,
        title=f"You matched with {display_name(interest.sender)}",
    )
    return match


def send_interest(sender, receiver_id, note=""):
    """
    Returns (interest, match_or_None, created). Repeating the request while an
    interest is pending is idempotent. If the receiver already sent a pending
    interest to the sender, it is accepted and a match is created.
    """
    Interest.objects.expire_due()
    if receiver_id == sender.id:
        raise exceptions.ValidationError({"receiver": "You cannot send an interest to yourself."})
    sender_profile = get_profile(sender)
    if not sender_profile.is_complete:
        raise exceptions.PermissionDenied("Complete your profile before sending interests.")
    if sender_profile.is_paused:
        raise exceptions.PermissionDenied("Reactivate your account to send interests.")
    receiver = User.objects.filter(pk=receiver_id).select_related("profile").first()
    if receiver is None or not hasattr(receiver, "profile") or not can_view_profile(sender, receiver.profile):
        raise exceptions.NotFound("This profile is not available.")
    if not receiver.profile.is_visible_in_discovery and not Interest.objects.filter(
        sender=receiver, receiver=sender, status=Interest.PENDING
    ).exists():
        raise exceptions.NotFound("This profile is not available.")
    if active_match_between(sender.id, receiver.id):
        raise Conflict("You are already matched with this member.")

    with transaction.atomic():
        existing = Interest.objects.select_for_update().filter(sender=sender, receiver=receiver, status=Interest.PENDING).first()
        if existing:
            return existing, None, False

        reverse = (
            Interest.objects.select_for_update()
            .filter(sender=receiver, receiver=sender, status=Interest.PENDING, expires_at__gt=timezone.now())
            .first()
        )
        if reverse:
            match = _accept(reverse)
            return reverse, match, False

        if receiver.profile.interests_from == "verified" and not is_verified(sender):
            raise exceptions.PermissionDenied("This member only accepts interests from verified members.")
        if Interest.objects.filter(
            sender=sender, receiver=receiver, status=Interest.DECLINED, responded_at__gt=_cooldown_start()
        ).exists():
            raise Conflict("This member declined your interest recently. You can try again later.")

        limit = entitlements_for(sender)["daily_interest_limit"]
        if limit is not None and interests_sent_today(sender) >= limit:
            raise exceptions.PermissionDenied(
                f"You've reached today's limit of {limit} interests. Upgrade to Premium for unlimited interests."
            )

        now = timezone.now()
        try:
            with transaction.atomic():
                interest = Interest.objects.create(
                    sender=sender,
                    receiver=receiver,
                    note=(note or "").strip()[:300],
                    created_at=now,
                    expires_at=now + timedelta(days=settings.PAIRD["INTEREST_EXPIRY_DAYS"]),
                )
        except IntegrityError:
            interest = Interest.objects.get(sender=sender, receiver=receiver, status=Interest.PENDING)
            return interest, None, False

    notify(
        receiver,
        Notification.INTEREST_RECEIVED,
        actor=sender,
        title=f"{display_name(sender)} sent you an interest",
        body="Respond within 7 days before it expires." if settings.PAIRD["INTEREST_EXPIRY_DAYS"] == 7 else "",
    )
    return interest, None, True


def _locked_interest(interest_id):
    interest = Interest.objects.select_for_update().select_related("sender", "receiver").filter(pk=interest_id).first()
    if interest is None:
        raise exceptions.NotFound("Interest not found.")
    return interest


def _ensure_pending(interest):
    # Callers run Interest.objects.expire_due() first (outside the transaction)
    # so expiry is persisted even though this raises and rolls back.
    if interest.status == Interest.PENDING and interest.expires_at <= timezone.now():
        raise Conflict("This interest has expired.")
    if interest.status != Interest.PENDING:
        raise Conflict(f"This interest is already {interest.status}.")


def accept_interest(user, interest_id):
    Interest.objects.expire_due()
    with transaction.atomic():
        return _accept_interest(user, interest_id)


def _accept_interest(user, interest_id):
    interest = _locked_interest(interest_id)
    if interest.receiver_id != user.id:
        raise exceptions.NotFound("Interest not found.")
    if is_blocked_between(interest.sender, interest.receiver) or not interest.sender.is_active:
        raise exceptions.NotFound("Interest not found.")
    _ensure_pending(interest)
    match = _accept(interest)
    return interest, match


def decline_interest(user, interest_id):
    Interest.objects.expire_due()
    with transaction.atomic():
        return _decline_interest(user, interest_id)


def _decline_interest(user, interest_id):
    interest = _locked_interest(interest_id)
    if interest.receiver_id != user.id:
        raise exceptions.NotFound("Interest not found.")
    _ensure_pending(interest)
    interest.status = Interest.DECLINED
    interest.responded_at = timezone.now()
    interest.save(update_fields=["status", "responded_at"])
    return interest


def withdraw_interest(user, interest_id):
    Interest.objects.expire_due()
    with transaction.atomic():
        return _withdraw_interest(user, interest_id)


def _withdraw_interest(user, interest_id):
    interest = _locked_interest(interest_id)
    if interest.sender_id != user.id:
        raise exceptions.NotFound("Interest not found.")
    _ensure_pending(interest)
    interest.status = Interest.WITHDRAWN
    interest.responded_at = timezone.now()
    interest.save(update_fields=["status", "responded_at"])
    return interest


@transaction.atomic
def end_match(user, match_id):
    match = Match.objects.select_for_update().filter(pk=match_id).filter(Q(user_a=user) | Q(user_b=user)).first()
    if match is None:
        raise exceptions.NotFound("Match not found.")
    if match.ended_at is None:
        match.ended_at = timezone.now()
        match.ended_by = user
        match.save(update_fields=["ended_at", "ended_by"])
    return match


def close_connections(a, b):
    """Used when a block is created: end matches and pending interests both ways."""
    now = timezone.now()
    match = active_match_between(a.id, b.id)
    if match:
        match.ended_at = now
        match.ended_by = a
        match.save(update_fields=["ended_at", "ended_by"])
    Interest.objects.filter(sender=a, receiver=b, status=Interest.PENDING).update(
        status=Interest.WITHDRAWN, responded_at=now
    )
    Interest.objects.filter(sender=b, receiver=a, status=Interest.PENDING).update(
        status=Interest.DECLINED, responded_at=now
    )
