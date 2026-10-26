from rest_framework import serializers

from profiles.serializers import display_name

from .models import Notification, NotificationPreference


class NotificationPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationPreference
        fields = ["interests", "matches", "messages", "account"]


class NotificationSerializer(serializers.ModelSerializer):
    actor_id = serializers.IntegerField(read_only=True)
    actor_name = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = ["id", "kind", "title", "body", "actor_id", "actor_name", "created_at", "read_at"]

    def get_actor_name(self, notification):
        return display_name(notification.actor) if notification.actor else None
