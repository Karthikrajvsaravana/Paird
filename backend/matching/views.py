from django.db.models import Q
from django.utils import timezone
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from core.throttles import ScopedThrottle
from profiles.serializers import member_card
from profiles.services import MATCH, OTHER, get_preference
from safety.services import blocked_user_ids
from verification.services import verified_user_ids

from . import services
from .compatibility import vibe_score
from .discovery import discover, parse_filters
from .models import Interest, Match


def _page_params(request, default_size=20, max_size=50):
    try:
        page = max(1, int(request.query_params.get("page", 1)))
    except (TypeError, ValueError):
        page = 1
    try:
        size = max(1, min(max_size, int(request.query_params.get("page_size", default_size))))
    except (TypeError, ValueError):
        size = default_size
    return page, size


class DiscoverView(APIView):
    def get(self, request):
        from profiles.services import get_profile

        if not get_profile(request.user).is_complete:
            raise exceptions.PermissionDenied("Complete your profile to start discovering matches.")
        filters = parse_filters(request.query_params)
        candidates = discover(request.user, filters)
        page, size = _page_params(request)
        start = (page - 1) * size
        page_items = candidates[start : start + size]

        ids = [p.user_id for p in page_items]
        verified = verified_user_ids(ids)
        connections = services.connection_map(request.user, ids)
        pref = get_preference(request.user)
        results = [
            member_card(
                profile,
                viewer=request.user,
                request=request,
                rel=OTHER,
                verified=profile.user_id in verified,
                vibe=vibe_score(pref, profile, OTHER),
                connection=connections[profile.user_id],
            )
            for profile in page_items
        ]
        return Response(
            {
                "count": len(candidates),
                "page": page,
                "page_size": size,
                "has_next": start + size < len(candidates),
                "results": results,
            }
        )


def _interest_payload(interest, viewer, request, verified):
    other = interest.receiver if interest.sender_id == viewer.id else interest.sender
    rel = MATCH if interest.status == Interest.ACCEPTED else OTHER
    now = timezone.now()
    status_value = interest.status
    if status_value == Interest.PENDING and interest.expires_at <= now:
        status_value = Interest.EXPIRED
    return {
        "id": interest.id,
        "direction": "sent" if interest.sender_id == viewer.id else "received",
        "status": status_value,
        "note": interest.note,
        "created_at": interest.created_at,
        "expires_at": interest.expires_at,
        "responded_at": interest.responded_at,
        "member": member_card(other.profile, viewer=viewer, request=request, rel=rel, verified=other.id in verified),
    }


class InterestListView(APIView):
    throttle_classes = [ScopedThrottle]
    throttle_scope = "interests"
    throttle_methods = ("POST",)

    def get(self, request):
        Interest.objects.expire_due()
        direction = request.query_params.get("direction", "received")
        status_filter = request.query_params.get("status", "pending")
        if direction not in ("received", "sent"):
            raise exceptions.ValidationError({"direction": "Use 'received' or 'sent'."})
        valid_statuses = {key for key, _ in Interest.STATUSES} | {"all"}
        if status_filter not in valid_statuses:
            raise exceptions.ValidationError({"status": "Invalid status filter."})

        qs = Interest.objects.filter(**{"receiver" if direction == "received" else "sender": request.user})
        if status_filter != "all":
            qs = qs.filter(status=status_filter)
        blocked = blocked_user_ids(request.user)
        other_field = "sender" if direction == "received" else "receiver"
        qs = (
            qs.exclude(**{f"{other_field}_id__in": blocked})
            .filter(**{f"{other_field}__is_active": True, f"{other_field}__profile__is_paused": False})
            .select_related(f"{other_field}__profile", f"{other_field}__identity")
        )
        page, size = _page_params(request)
        total = qs.count()
        items = list(qs[(page - 1) * size : page * size])
        verified = verified_user_ids([getattr(i, f"{other_field}_id") for i in items])
        return Response(
            {
                "count": total,
                "page": page,
                "has_next": page * size < total,
                "results": [_interest_payload(i, request.user, request, verified) for i in items],
            }
        )

    def post(self, request):
        try:
            receiver_id = int(request.data.get("receiver_id"))
        except (TypeError, ValueError):
            raise exceptions.ValidationError({"receiver_id": "Choose a member to send an interest to."}) from None
        note = request.data.get("note", "")
        if not isinstance(note, str):
            raise exceptions.ValidationError({"note": "Invalid note."})
        interest, match, created = services.send_interest(request.user, receiver_id, note)
        interest.refresh_from_db()
        verified = verified_user_ids([interest.sender_id, interest.receiver_id])
        body = {"interest": _interest_payload(interest, request.user, request, verified), "match": None}
        if match:
            body["match"] = {"id": match.id, "conversation_id": match.conversation.id}
        return Response(body, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)


class InterestActionView(APIView):
    throttle_classes = [ScopedThrottle]
    throttle_scope = "interests"

    def post(self, request, interest_id, action):
        if action == "accept":
            interest, match = services.accept_interest(request.user, interest_id)
            body = {"match": {"id": match.id, "conversation_id": match.conversation.id}}
        elif action == "decline":
            interest = services.decline_interest(request.user, interest_id)
            body = {}
        elif action == "withdraw":
            interest = services.withdraw_interest(request.user, interest_id)
            body = {}
        else:
            raise exceptions.NotFound()
        verified = verified_user_ids([interest.sender_id, interest.receiver_id])
        body["interest"] = _interest_payload(interest, request.user, request, verified)
        return Response(body)


def _match_payload(match, viewer, request, verified, unread):
    other = match.user_b if match.user_a_id == viewer.id else match.user_a
    conversation = getattr(match, "conversation", None)
    return {
        "id": match.id,
        "created_at": match.created_at,
        "conversation_id": conversation.id if conversation else None,
        "unread_count": unread.get(conversation.id, 0) if conversation else 0,
        "member": member_card(other.profile, viewer=viewer, request=request, rel=MATCH, verified=other.id in verified),
    }


class MatchListView(APIView):
    def get(self, request):
        from messaging.services import unread_counts

        blocked = blocked_user_ids(request.user)
        qs = (
            Match.objects.filter(Q(user_a=request.user) | Q(user_b=request.user), ended_at__isnull=True)
            .exclude(user_a_id__in=blocked)
            .exclude(user_b_id__in=blocked)
            .select_related("user_a__profile", "user_b__profile", "user_a__identity", "user_b__identity", "conversation")
        )
        matches = [m for m in qs if m.other(request.user).is_active]
        page, size = _page_params(request)
        items = matches[(page - 1) * size : page * size]
        verified = verified_user_ids([m.other_id(request.user) for m in items])
        unread = unread_counts(request.user, [m.conversation.id for m in items if hasattr(m, "conversation")])
        return Response(
            {
                "count": len(matches),
                "page": page,
                "has_next": page * size < len(matches),
                "results": [_match_payload(m, request.user, request, verified, unread) for m in items],
            }
        )


class EndMatchView(APIView):
    def post(self, request, match_id):
        services.end_match(request.user, match_id)
        return Response(status=status.HTTP_204_NO_CONTENT)
