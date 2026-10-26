from django.contrib import admin

from .models import Interest, Match


@admin.register(Interest)
class InterestAdmin(admin.ModelAdmin):
    list_display = ["id", "sender", "receiver", "status", "created_at", "expires_at"]
    list_filter = ["status"]
    raw_id_fields = ["sender", "receiver"]


@admin.register(Match)
class MatchAdmin(admin.ModelAdmin):
    list_display = ["id", "user_a", "user_b", "created_at", "ended_at"]
    raw_id_fields = ["user_a", "user_b", "interest", "ended_by"]
