from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from rest_framework import exceptions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from core.throttles import ScopedThrottle
from matching.services import close_connections
from messaging.models import Message
from profiles.serializers import display_name

from .models import Block, Report

User = get_user_model()


def _target(user_id, viewer):
    try:
        user_id = int(user_id)
    except (TypeError, ValueError):
        raise exceptions.ValidationError({"user_id": "Choose a member."}) from None
    if user_id == viewer.id:
        raise exceptions.ValidationError({"user_id": "You cannot do this to yourself."})
    target = User.objects.filter(pk=user_id).first()
    if target is None:
        raise exceptions.NotFound("Member not found.")
    return target


class BlockListView(APIView):
    def get(self, request):
        blocks = Block.objects.filter(blocker=request.user).select_related("blocked__identity").order_by("-created_at")
        return Response(
            [
                {"user_id": b.blocked_id, "display_name": display_name(b.blocked), "created_at": b.created_at}
                for b in blocks
            ]
        )

    def post(self, request):
        target = _target(request.data.get("user_id"), request.user)
        with transaction.atomic():
            try:
                with transaction.atomic():
                    Block.objects.create(blocker=request.user, blocked=target)
            except IntegrityError:
                pass  # already blocked — idempotent
            close_connections(request.user, target)
        return Response(status=status.HTTP_204_NO_CONTENT)


class UnblockView(APIView):
    def delete(self, request, user_id):
        Block.objects.filter(blocker=request.user, blocked_id=user_id).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class ReportSerializer(serializers.Serializer):
    user_id = serializers.IntegerField()
    reason = serializers.ChoiceField(choices=Report.REASONS)
    details = serializers.CharField(max_length=1000, required=False, allow_blank=True)
    message_id = serializers.IntegerField(required=False, allow_null=True)
    block = serializers.BooleanField(required=False, default=False)


class ReportView(APIView):
    throttle_classes = [ScopedThrottle]
    throttle_scope = "reports"

    def post(self, request):
        serializer = ReportSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        target = _target(data["user_id"], request.user)
        message = None
        if data.get("message_id"):
            # Only messages the reporter could actually see, sent by the target.
            message = (
                Message.objects.filter(pk=data["message_id"], sender=target)
                .filter(conversation__match__user_a__in=[request.user, target], conversation__match__user_b__in=[request.user, target])
                .first()
            )
            if message is None:
                raise exceptions.ValidationError({"message_id": "Message not found."})
        Report.objects.create(
            reporter=request.user,
            reported_user=target,
            reason=data["reason"],
            details=data.get("details", "").strip(),
            message=message,
        )
        if data.get("block"):
            with transaction.atomic():
                Block.objects.get_or_create(blocker=request.user, blocked=target)
                close_connections(request.user, target)
        return Response({"detail": "Thanks for letting us know. Our team will review this report."}, status=status.HTTP_201_CREATED)


class ReportReasonsView(APIView):
    def get(self, request):
        return Response([{"value": k, "label": v} for k, v in Report.REASONS])
