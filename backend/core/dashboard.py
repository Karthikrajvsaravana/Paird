from datetime import timedelta

from django.db.models import Q
from django.utils import timezone
from rest_framework.response import Response
from rest_framework.views import APIView

from matching.compatibility import vibe_score
from matching.discovery import recommendations
from matching.models import Interest, Match
from matching.services import connection_map
from messaging.services import total_unread
from notifications.models import Notification
from profiles.serializers import member_card
from profiles.services import OTHER, completion_percentage, get_preference, get_profile, missing_required
from safety.services import blocked_user_ids
from subscriptions.entitlements import entitlements_for
from verification.services import verification_status, verified_user_ids


class DashboardView(APIView):
    """Everything the home screen needs, computed from real data."""

    def get(self, request):
        user = request.user
        Interest.objects.expire_due()
        profile = get_profile(user)
        preference = get_preference(user)
        blocked = blocked_user_ids(user)
        now = timezone.now()

        received = Interest.objects.filter(receiver=user, status=Interest.PENDING).exclude(sender_id__in=blocked)
        sent = Interest.objects.filter(sender=user, status=Interest.PENDING).exclude(receiver_id__in=blocked)
        matches = (
            Match.objects.filter(Q(user_a=user) | Q(user_b=user), ended_at__isnull=True)
            .exclude(user_a_id__in=blocked)
            .exclude(user_b_id__in=blocked)
        )
        expiring_soon = received.filter(expires_at__lte=now + timedelta(hours=24)).count()
        verification = verification_status(user)

        notices = []
        missing = missing_required(profile, preference)
        if not profile.is_complete:
            notices.append({"kind": "complete_profile", "message": "Finish your profile so others can discover you."})
        if profile.is_paused:
            notices.append({"kind": "paused", "message": "Your account is deactivated and hidden from discovery."})
        elif profile.is_complete and not profile.discoverable:
            notices.append({"kind": "hidden", "message": "Your profile is hidden from discovery."})
        if expiring_soon:
            notices.append(
                {"kind": "interests_expiring", "message": f"{expiring_soon} interest(s) expire within 24 hours."}
            )
        if verification == "unverified" and profile.is_complete:
            notices.append({"kind": "verify", "message": "Get photo verified to build trust with your matches."})
        if verification == "rejected":
            notices.append({"kind": "verification_rejected", "message": "Your verification was not approved. You can try again."})
        if not user.photos.exists():
            notices.append({"kind": "add_photo", "message": "Add a photo — profiles with photos get more interests."})

        recs = []
        if profile.is_complete:
            rec_profiles = recommendations(user, limit=5)
            ids = [p.user_id for p in rec_profiles]
            verified = verified_user_ids(ids)
            connections = connection_map(user, ids)
            recs = [
                member_card(
                    p,
                    viewer=user,
                    request=request,
                    rel=OTHER,
                    verified=p.user_id in verified,
                    vibe=vibe_score(preference, p, OTHER),
                    connection=connections[p.user_id],
                )
                for p in rec_profiles
            ]

        return Response(
            {
                "profile": {
                    "is_complete": profile.is_complete,
                    "completion": completion_percentage(profile),
                    "missing_required": missing,
                    "onboarding_step": profile.onboarding_step,
                    "is_paused": profile.is_paused,
                    "discoverable": profile.discoverable,
                },
                "counts": {
                    "interests_received": received.count(),
                    "interests_sent": sent.count(),
                    "matches": matches.count(),
                    "unread_messages": total_unread(user),
                    "unread_notifications": Notification.objects.filter(user=user, read_at__isnull=True)
                    .exclude(actor_id__in=blocked)
                    .count(),
                },
                "verification_status": verification,
                "subscription": entitlements_for(user),
                "notices": notices,
                "recommendations": recs,
            }
        )
