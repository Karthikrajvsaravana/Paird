from django.contrib import admin

from .models import PartnerPreference, Photo, Profile


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ["user", "gender", "city", "country", "completed_at", "discoverable", "is_paused", "last_active_at"]
    list_filter = ["gender", "discoverable", "is_paused"]
    search_fields = ["user__identity__full_name", "city", "country"]
    raw_id_fields = ["user"]


@admin.register(Photo)
class PhotoAdmin(admin.ModelAdmin):
    list_display = ["id", "user", "is_primary", "position", "created_at"]
    raw_id_fields = ["user"]


admin.site.register(PartnerPreference)
