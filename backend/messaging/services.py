from django.conf import settings
from django.db import transaction
from django.db.models import Q
from rest_framework import exceptions

from safety.services import is_blocked_between
from verification.services import is_verified

from .models import Conversation, ConversationReadState, Message


def conversation_for(user, conversation_id):
    """Return the conversation if the user is a participant, else 404."""
    conversation = (
        Conversation.objects.select_related("match", "match__user_a__profile", "match__user_b__profile")
        .filter(pk=conversation_id)
        .filter(Q(match__user_a=user) | Q(match__user_b=user))
        .first()
    )
    if conversation is None:
        raise exceptions.NotFound("Conversation not found.")
    other = conversation.match.other(user)
    if is_blocked_between(user, other):
        raise exceptions.NotFound("Conversation not found.")
    return conversation


def can_send(user, conversation):
    """Return (allowed, reason)."""
    match = conversation.match
    other = match.other(user)
    if not match.is_active:
        return False, "This match has ended."
    if not other.is_active or other.profile.is_paused:
        return False, "This member isn't available right now."
    if user.profile.is_paused:
        return False, "Reactivate your account to send messages."
    if other.profile.messages_from == "verified_matches" and not is_verified(user):
        return False, "This member only receives messages from verified matches."
    return True, None


def send_message(user, conversation_id, body):
    conversation = conversation_for(user, conversation_id)
    body = (body or "").strip() if isinstance(body, str) else ""
    if not body:
        raise exceptions.ValidationError({"body": "Message cannot be empty."})
    if len(body) > settings.PAIRD["MESSAGE_MAX_LENGTH"]:
        raise exceptions.ValidationError({"body": f"Messages can be up to {settings.PAIRD['MESSAGE_MAX_LENGTH']} characters."})
    allowed, reason = can_send(user, conversation)
    if not allowed:
        raise exceptions.PermissionDenied(reason)
    with transaction.atomic():
        message = Message.objects.create(conversation=conversation, sender=user, body=body)
        Conversation.objects.filter(pk=conversation.pk).update(last_message_at=message.created_at)
        mark_read(user, conversation, message.id)
    return message


def mark_read(user, conversation, up_to_id=None):
    if up_to_id is None:
        up_to_id = conversation.messages.order_by("-id").values_list("id", flat=True).first() or 0
    state, _ = ConversationReadState.objects.get_or_create(conversation=conversation, user=user)
    if up_to_id > state.last_read_message_id:
        state.last_read_message_id = up_to_id
        state.save(update_fields=["last_read_message_id", "updated_at"])
    return state


def read_marker(user, conversation_ids):
    return dict(
        ConversationReadState.objects.filter(user=user, conversation_id__in=conversation_ids).values_list(
            "conversation_id", "last_read_message_id"
        )
    )


def unread_counts(user, conversation_ids):
    conversation_ids = list(conversation_ids)
    if not conversation_ids:
        return {}
    markers = read_marker(user, conversation_ids)
    counts = {}
    for cid in conversation_ids:
        counts[cid] = (
            Message.objects.filter(conversation_id=cid, id__gt=markers.get(cid, 0)).exclude(sender=user).count()
        )
    return counts


def total_unread(user):
    from safety.services import blocked_user_ids

    blocked = blocked_user_ids(user)
    ids = list(
        Conversation.objects.filter(Q(match__user_a=user) | Q(match__user_b=user))
        .exclude(match__user_a_id__in=blocked)
        .exclude(match__user_b_id__in=blocked)
        .values_list("id", flat=True)
    )
    return sum(unread_counts(user, ids).values())
