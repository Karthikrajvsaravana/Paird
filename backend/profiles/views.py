from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Max
from django.http import FileResponse, HttpResponseRedirect
from django.utils import timezone
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from core.throttles import ScopedThrottle
from matching.compatibility import vibe_score
from matching.services import connection_map
from verification.services import is_verified

from . import choices as c
from .models import Photo, Profile
from .serializers import OwnProfileSerializer, PartnerPreferenceSerializer, PhotoSerializer, public_profile
from .services import (
    ONBOARDING_STEPS,
    audience_allows,
    can_view_profile,
    delete_stored_file,
    get_preference,
    get_profile,
    missing_required,
    process_image_upload,
    relationship,
)

User = get_user_model()


class OptionsView(APIView):
    """Choice sets and limits used by the app's forms (single source of truth)."""

    def get(self, request):
        return Response(
            {
                "choices": {name: [{"value": k, "label": v} for k, v in values] for name, values in c.ALL_CHOICES.items()},
                "min_age": settings.PAIRD["MIN_AGE"],
                "onboarding_steps": ONBOARDING_STEPS,
                "photo_max_count": settings.PHOTO_MAX_PER_PROFILE,
                "photo_max_bytes": settings.PHOTO_MAX_UPLOAD_BYTES,
                "interest_expiry_days": settings.PAIRD["INTEREST_EXPIRY_DAYS"],
                "message_max_length": settings.PAIRD["MESSAGE_MAX_LENGTH"],
            }
        )


class MyProfileView(APIView):
    def get(self, request):
        profile = get_profile(request.user)
        return Response(OwnProfileSerializer(profile, context={"request": request}).data)

    def patch(self, request):
        profile = get_profile(request.user)
        serializer = OwnProfileSerializer(profile, data=request.data, partial=True, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(OwnProfileSerializer(profile, context={"request": request}).data)


class PublishProfileView(APIView):
    """Finish onboarding: validates required fields and publishes the profile."""

    def post(self, request):
        profile = get_profile(request.user)
        missing = missing_required(profile, get_preference(request.user))
        if missing:
            raise exceptions.ValidationError(
                {"missing_required": missing, "detail": "Please complete the required sections first."}
            )
        if profile.completed_at is None:
            profile.completed_at = timezone.now()
            profile.onboarding_step = len(ONBOARDING_STEPS)
            profile.last_active_at = timezone.now()
            profile.save(update_fields=["completed_at", "onboarding_step", "last_active_at", "updated_at"])
        return Response(OwnProfileSerializer(profile, context={"request": request}).data)


class PartnerPreferenceView(APIView):
    def get(self, request):
        return Response(PartnerPreferenceSerializer(get_preference(request.user)).data)

    def put(self, request):
        return self._save(request, partial=False)

    def patch(self, request):
        return self._save(request, partial=True)

    def _save(self, request, partial):
        serializer = PartnerPreferenceSerializer(get_preference(request.user), data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class PhotoListView(APIView):
    throttle_classes = [ScopedThrottle]
    throttle_scope = "uploads"
    throttle_methods = ("POST",)

    def get(self, request):
        photos = Photo.objects.filter(user=request.user)
        return Response(PhotoSerializer(photos, many=True, context={"request": request}).data)

    def post(self, request):
        upload = request.FILES.get("image")
        if upload is None:
            raise exceptions.ValidationError({"image": "Choose a photo to upload."})
        try:
            content = process_image_upload(upload)
        except DjangoValidationError as exc:
            raise exceptions.ValidationError({"image": exc.messages}) from None

        with transaction.atomic():
            # Lock the member's profile row to serialise concurrent uploads.
            Profile.objects.select_for_update().filter(user=request.user).first()
            existing = Photo.objects.filter(user=request.user)
            if existing.count() >= settings.PHOTO_MAX_PER_PROFILE:
                raise exceptions.ValidationError(
                    {"image": f"You can upload up to {settings.PHOTO_MAX_PER_PROFILE} photos."}
                )
            next_position = (existing.aggregate(m=Max("position"))["m"] or 0) + 1
            photo = Photo(
                user=request.user,
                position=next_position,
                is_primary=not existing.exists(),
                width=content.width,
                height=content.height,
            )
            photo.image.save(content.name, content, save=False)
            photo.save()
        return Response(PhotoSerializer(photo, context={"request": request}).data, status=status.HTTP_201_CREATED)


class PhotoDetailView(APIView):
    def _own(self, request, photo_id):
        photo = Photo.objects.filter(pk=photo_id, user=request.user).first()
        if photo is None:
            raise exceptions.NotFound("Photo not found.")
        return photo

    def patch(self, request, photo_id):
        photo = self._own(request, photo_id)
        if request.data.get("is_primary") is True:
            with transaction.atomic():
                Photo.objects.filter(user=request.user, is_primary=True).exclude(pk=photo.pk).update(is_primary=False)
                photo.is_primary = True
                photo.save(update_fields=["is_primary"])
        if "position" in request.data:
            try:
                position = int(request.data["position"])
            except (TypeError, ValueError):
                raise exceptions.ValidationError({"position": "Enter a valid position."}) from None
            photo.position = max(0, min(position, 100))
            photo.save(update_fields=["position"])
        return Response(PhotoSerializer(photo, context={"request": request}).data)

    def delete(self, request, photo_id):
        photo = self._own(request, photo_id)
        image = photo.image
        with transaction.atomic():
            was_primary = photo.is_primary
            photo.delete()
            if was_primary:
                next_photo = Photo.objects.filter(user=request.user).order_by("position", "id").first()
                if next_photo:
                    next_photo.is_primary = True
                    next_photo.save(update_fields=["is_primary"])
        delete_stored_file(image)
        return Response(status=status.HTTP_204_NO_CONTENT)


class PhotoFileView(APIView):
    """Streams a photo after checking the owner's photo-visibility setting."""

    def get(self, request, photo_id):
        photo = Photo.objects.select_related("user__profile").filter(pk=photo_id).first()
        if photo is None:
            raise exceptions.NotFound()
        if photo.user_id != request.user.id:
            profile = photo.user.profile
            if not can_view_profile(request.user, profile):
                raise exceptions.NotFound()
            if not audience_allows(profile.photo_visibility, relationship(request.user, photo.user_id)):
                raise exceptions.NotFound()
        if settings.STORAGE_BACKEND == "s3":
            return HttpResponseRedirect(photo.image.url)  # short-lived signed URL
        response = FileResponse(photo.image.open("rb"), content_type="image/jpeg")
        response["Cache-Control"] = "private, max-age=300"
        response["X-Content-Type-Options"] = "nosniff"
        return response


class MemberProfileView(APIView):
    """Another member's profile, filtered by their privacy settings."""

    def get(self, request, user_id):
        profile = Profile.objects.select_related("user", "user__identity").filter(user_id=user_id).first()
        if profile is None or not can_view_profile(request.user, profile):
            raise exceptions.NotFound("This profile is not available.")
        if profile.user_id == request.user.id:
            rel = "self"
            connection = None
            vibe = None
        else:
            rel = relationship(request.user, user_id)
            connection = connection_map(request.user, [user_id])[user_id]
            vibe = vibe_score(get_preference(request.user), profile, rel)
        return Response(
            public_profile(
                profile,
                viewer=request.user,
                request=request,
                rel=rel,
                connection=connection,
                vibe=vibe,
                verified=is_verified(profile.user),
            )
        )
