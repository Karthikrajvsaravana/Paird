from django.db.models import Q
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from core.throttles import ScopedThrottle
from profiles.serializers import member_card
from profiles.services import MATCH, OTHER
from safety.services import blocked_user_ids
from verification.services import verified_user_ids

from . import services
from .models import Conversation, ConversationReadState, Message


def message_payload(message, viewer, other_read_up_to):
    mine = message.sender_id == viewer.id
    return {
        "id": message.id,
        "body": message.body,
        "sender_id": message.sender_id,
        "is_mine": mine,
        "created_at": message.created_at,
        "is_read": (message.id <= other_read_up_to) if mine else None,
    }


class ConversationListView(APIView):
    """Conversations for the member's matches (active and ended), newest first."""

    def get(self, request):
        blocked = blocked_user_ids(request.user)
        conversations = list(
            Conversation.objects.filter(Q(match__user_a=request.user) | Q(match__user_b=request.user))
            .exclude(match__user_a_id__in=blocked)
            .exclude(match__user_b_id__in=blocked)
            .select_related("match__user_a__profile", "match__user_b__profile", "match__user_a__identity", "match__user_b__identity")
            .order_by("-last_message_at", "-created_at")
        )
        conversations = [c for c in conversations if c.match.other(request.user).is_active]
        ids = [c.id for c in conversations]
        unread = services.unread_counts(request.user, ids)
        verified = verified_user_ids([c.match.other_id(request.user) for c in conversations])
        last_messages = {}
        for conversation in conversations:
            last = conversation.messages.order_by("-id").first()
            last_messages[conversation.id] = last
        results = []
        for conversation in conversations:
            other = conversation.match.other(request.user)
            last = last_messages[conversation.id]
            rel = MATCH if conversation.match.is_active else OTHER
            results.append(
                {
                    "id": conversation.id,
                    "match_id": conversation.match_id,
                    "is_active": conversation.match.is_active,
                    "unread_count": unread.get(conversation.id, 0),
                    "last_message": (
                        {
                            "body": last.body[:140],
                            "is_mine": last.sender_id == request.user.id,
                            "created_at": last.created_at,
                        }
                        if last
                        else None
                    ),
                    "updated_at": conversation.last_message_at or conversation.created_at,
                    "member": member_card(
                        other.profile, viewer=request.user, request=request, rel=rel, verified=other.id in verified
                    ),
                }
            )
        return Response({"count": len(results), "results": results})


class MessageListView(APIView):
    """
    GET  ?before=<id>  older history (page of up to 30, newest first)
    GET  ?after=<id>   new messages since the last one the client has (polling)
    POST {"body": "..."}
    """

    throttle_classes = [ScopedThrottle]
    throttle_scope = "messages"
    throttle_methods = ("POST",)

    def get(self, request, conversation_id):
        conversation = services.conversation_for(request.user, conversation_id)
        qs = Message.objects.filter(conversation=conversation)
        limit = 30
        try:
            if request.query_params.get("after"):
                qs = qs.filter(id__gt=int(request.query_params["after"])).order_by("id")[:100]
                messages = list(qs)
                messages.reverse()
            else:
                if request.query_params.get("before"):
                    qs = qs.filter(id__lt=int(request.query_params["before"]))
                messages = list(qs.order_by("-id")[: limit + 1])
        except ValueError:
            raise exceptions.ValidationError({"detail": "Invalid cursor."}) from None
        has_more = False
        if not request.query_params.get("after"):
            has_more = len(messages) > limit
            messages = messages[:limit]

        if messages:
            services.mark_read(request.user, conversation, max(m.id for m in messages))
        other = conversation.match.other(request.user)
        other_state = ConversationReadState.objects.filter(conversation=conversation, user=other).first()
        other_read = other_state.last_read_message_id if other_state else 0
        allowed, reason = services.can_send(request.user, conversation)
        rel = MATCH if conversation.match.is_active else OTHER
        return Response(
            {
                "conversation": {
                    "id": conversation.id,
                    "match_id": conversation.match_id,
                    "is_active": conversation.match.is_active,
                    "can_send": allowed,
                    "cannot_send_reason": reason,
                    "member": member_card(
                        other.profile,
                        viewer=request.user,
                        request=request,
                        rel=rel,
                        verified=bool(verified_user_ids([other.id])),
                    ),
                },
                "results": [message_payload(m, request.user, other_read) for m in messages],
                "has_more": has_more,
                "other_read_up_to": other_read,
            }
        )

    def post(self, request, conversation_id):
        message = services.send_message(request.user, conversation_id, request.data.get("body"))
        return Response(message_payload(message, request.user, 0), status=status.HTTP_201_CREATED)


class MarkReadView(APIView):
    def post(self, request, conversation_id):
        conversation = services.conversation_for(request.user, conversation_id)
        services.mark_read(request.user, conversation)
        return Response(status=status.HTTP_204_NO_CONTENT)
