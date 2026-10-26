from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from core.throttles import ScopedThrottle
from profiles.models import Photo
from profiles.services import process_image_upload

from .models import VerificationRequest
from .services import verification_status

METHOD_DESCRIPTION = (
    "Photo verification: take a selfie and the Paird team compares it with your profile photos. "
    "We don't ask for identity documents. Your selfie is deleted once it has been reviewed."
)


def _payload(user):
    latest = VerificationRequest.objects.filter(user=user).first()
    return {
        "status": verification_status(user),
        "method": "photo_review",
        "description": METHOD_DESCRIPTION,
        "submitted_at": latest.submitted_at if latest else None,
        "reviewed_at": latest.reviewed_at if latest else None,
        "rejection_reason": latest.rejection_reason if latest and latest.status == VerificationRequest.REJECTED else "",
        "can_submit": not VerificationRequest.objects.filter(user=user, status=VerificationRequest.PENDING).exists(),
    }


class VerificationView(APIView):
    throttle_classes = [ScopedThrottle]
    throttle_scope = "uploads"

    def get(self, request):
        return Response(_payload(request.user))

    def post(self, request):
        if not Photo.objects.filter(user=request.user).exists():
            raise exceptions.ValidationError({"selfie": "Add at least one profile photo before requesting verification."})
        upload = request.FILES.get("selfie")
        if upload is None:
            raise exceptions.ValidationError({"selfie": "Take a selfie to submit for review."})
        try:
            content = process_image_upload(upload)
        except DjangoValidationError as exc:
            raise exceptions.ValidationError({"selfie": exc.messages}) from None
        try:
            with transaction.atomic():
                request_obj = VerificationRequest(user=request.user)
                request_obj.selfie.save(content.name, content, save=False)
                request_obj.save()
        except IntegrityError:
            raise exceptions.ValidationError({"selfie": "Your verification is already being reviewed."}) from None
        return Response(_payload(request.user), status=status.HTTP_201_CREATED)
