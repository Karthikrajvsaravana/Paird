from django.contrib import admin

from .models import Subscription


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = ["id", "user", "plan", "status", "source", "starts_at", "expires_at"]
    list_filter = ["status", "source", "plan"]
    raw_id_fields = ["user"]
