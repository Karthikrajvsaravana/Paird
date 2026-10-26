from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from safety.services import blocked_user_ids

from .models import Notification
from .serializers import NotificationSerializer


class NotificationListView(APIView):
    def get(self, request):
        blocked = blocked_user_ids(request.user)
        qs = Notification.objects.filter(user=request.user).exclude(actor_id__in=blocked).select_related("actor__identity")
        items = list(qs[:50])
        return Response(
            {
                "unread_count": qs.filter(read_at__isnull=True).count(),
                "results": NotificationSerializer(items, many=True).data,
            }
        )


class NotificationReadAllView(APIView):
    def post(self, request):
        Notification.objects.filter(user=request.user, read_at__isnull=True).update(read_at=timezone.now())
        return Response(status=status.HTTP_204_NO_CONTENT)
