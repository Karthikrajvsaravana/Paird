from django.contrib import admin

from .models import Block, Report


@admin.register(Report)
class ReportAdmin(admin.ModelAdmin):
    list_display = ["id", "reported_user", "reason", "status", "created_at"]
    list_filter = ["status", "reason"]
    raw_id_fields = ["reporter", "reported_user", "message"]


@admin.register(Block)
class BlockAdmin(admin.ModelAdmin):
    list_display = ["id", "blocker", "blocked", "created_at"]
    raw_id_fields = ["blocker", "blocked"]
