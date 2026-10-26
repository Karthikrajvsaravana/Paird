from datetime import timedelta

from django.utils import timezone
from rest_framework_simplejwt.authentication import JWTAuthentication

ACTIVITY_RESOLUTION = timedelta(minutes=5)


class ActivityTrackingJWTAuthentication(JWTAuthentication):
    """JWT authentication that records coarse "last active" time (5 min resolution)."""

    def authenticate(self, request):
        result = super().authenticate(request)
        if result is not None:
            from profiles.models import Profile

            user = result[0]
            now = timezone.now()
            Profile.objects.filter(user=user, completed_at__isnull=False).exclude(
                last_active_at__gt=now - ACTIVITY_RESOLUTION
            ).update(last_active_at=now)
        return result
