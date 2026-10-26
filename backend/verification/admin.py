from django.contrib import admin, messages
from django.utils import timezone
from django.utils.html import format_html

from notifications.models import Notification
from notifications.services import notify
from profiles.models import Photo
from profiles.services import delete_stored_file

from .models import VerificationRequest


def _decide(modeladmin, request, queryset, status_value, reason=""):
    count = 0
    for item in queryset.filter(status=VerificationRequest.PENDING):
        item.status = status_value
        item.reviewed_at = timezone.now()
        item.reviewed_by = request.user
        item.rejection_reason = reason
        selfie = item.selfie
        item.selfie = None
        item.save()
        delete_stored_file(selfie)
        notify(
            item.user,
            Notification.VERIFICATION_UPDATED,
            title="Your profile is now photo verified" if status_value == VerificationRequest.APPROVED
            else "Your verification needs another try",
            body="" if status_value == VerificationRequest.APPROVED else reason,
        )
        count += 1
    modeladmin.message_user(request, f"{count} request(s) updated; selfies deleted.", messages.SUCCESS)


@admin.action(description="Approve: selfie matches profile photos")
def approve(modeladmin, request, queryset):
    _decide(modeladmin, request, queryset, VerificationRequest.APPROVED)


@admin.action(description="Reject: selfie does not clearly match")
def reject(modeladmin, request, queryset):
    _decide(
        modeladmin,
        request,
        queryset,
        VerificationRequest.REJECTED,
        "We couldn't match your selfie to your profile photos. Please try again in good lighting.",
    )


@admin.register(VerificationRequest)
class VerificationRequestAdmin(admin.ModelAdmin):
    list_display = ["id", "user", "status", "submitted_at", "reviewed_at"]
    list_filter = ["status"]
    readonly_fields = ["user", "selfie_preview", "profile_photos", "status", "submitted_at", "reviewed_at", "reviewed_by"]
    exclude = ["selfie"]
    actions = [approve, reject]

    def has_add_permission(self, request):
        return False

    @admin.display(description="Selfie")
    def selfie_preview(self, obj):
        if not obj.selfie:
            return "Deleted after review"
        import base64

        data = base64.b64encode(obj.selfie.read()).decode()
        return format_html('<img src="data:image/jpeg;base64,{}" style="max-width:320px">', data)

    @admin.display(description="Profile photos")
    def profile_photos(self, obj):
        import base64

        html = []
        for photo in Photo.objects.filter(user=obj.user)[:6]:
            data = base64.b64encode(photo.image.read()).decode()
            html.append(format_html('<img src="data:image/jpeg;base64,{}" style="max-width:160px;margin:4px">', data))
        return format_html("".join(str(h) for h in html)) if html else "No photos"
