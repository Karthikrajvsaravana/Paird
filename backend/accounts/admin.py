from django.contrib import admin

from .models import AccountIdentity


@admin.register(AccountIdentity)
class AccountIdentityAdmin(admin.ModelAdmin):
    list_display = ["user", "full_name", "email", "phone", "created_at"]
    search_fields = ["full_name", "email", "phone"]
    raw_id_fields = ["user"]
