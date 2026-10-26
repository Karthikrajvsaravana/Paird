from django.db import transaction
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView

from core.exceptions import ServiceUnavailable
from core.throttles import ScopedThrottle
from notifications.services import get_preferences
from profiles.serializers import PrivacySettingsSerializer
from profiles.services import completion_percentage, get_profile, missing_required, get_preference
from subscriptions.entitlements import entitlements_for
from verification.services import verification_status

from . import serializers as s
from .identifiers import EMAIL
from .models import AccountIdentity
from .services import (
    confirm_password_reset,
    create_account,
    delete_account,
    email_delivery_configured,
    issue_tokens,
    revoke_all_tokens,
    start_password_reset,
)


def account_payload(user):
    identity = getattr(user, "identity", None)
    profile = get_profile(user)
    return {
        "id": user.id,
        "full_name": identity.full_name if identity else user.first_name,
        "email": identity.email if identity else user.email or None,
        "phone": identity.phone if identity else None,
        "profile_complete": profile.is_complete,
        "onboarding_step": profile.onboarding_step,
        "profile_completion": completion_percentage(profile),
        "missing_required": missing_required(profile, get_preference(user)),
        "is_paused": profile.is_paused,
        "verification_status": verification_status(user),
        "subscription": entitlements_for(user),
        "date_joined": user.date_joined,
    }


class AuthThrottleMixin:
    throttle_classes = [ScopedThrottle]
    throttle_scope = "auth"


class RegisterView(AuthThrottleMixin, APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        serializer = s.RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        kind, identifier = serializer.validated_data["identifier"]
        user = create_account(
            serializer.validated_data["full_name"], kind, identifier, serializer.validated_data["password"]
        )
        return Response({"tokens": issue_tokens(user), "user": account_payload(user)}, status=status.HTTP_201_CREATED)


class LoginView(AuthThrottleMixin, APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        serializer = s.LoginSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        return Response({"tokens": issue_tokens(user), "user": account_payload(user)})


class RefreshView(AuthThrottleMixin, TokenRefreshView):
    authentication_classes = []
    throttle_scope = "auth"


class LogoutView(AuthThrottleMixin, APIView):
    """Revoke a refresh token. Works even when the access token has expired."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        token = request.data.get("refresh")
        if isinstance(token, str) and token:
            try:
                RefreshToken(token).blacklist()
            except TokenError:
                pass  # Already invalid: logging out is still successful.
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(APIView):
    def get(self, request):
        return Response(account_payload(request.user))

    def patch(self, request):
        serializer = s.UpdateAccountSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        full_name = serializer.validated_data["full_name"]
        with transaction.atomic():
            AccountIdentity.objects.filter(user=request.user).update(full_name=full_name)
            request.user.first_name = full_name[:150]
            request.user.save(update_fields=["first_name"])
        request.user.refresh_from_db()
        return Response(account_payload(request.user))


class ChangePasswordView(AuthThrottleMixin, APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = s.ChangePasswordSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        user = request.user
        user.set_password(serializer.validated_data["new_password"])
        user.save(update_fields=["password"])
        revoke_all_tokens(user)
        return Response({"tokens": issue_tokens(user)})


class PasswordResetRequestView(AuthThrottleMixin, APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        serializer = s.PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        kind, identifier = serializer.validated_data["identifier"]
        if kind != EMAIL:
            raise ServiceUnavailable(
                "Password reset by SMS isn't available yet. Please contact support to reset your password."
            )
        if not email_delivery_configured():
            raise ServiceUnavailable("Password reset emails aren't configured on this server yet.")
        identity = AccountIdentity.objects.select_related("user").filter(email=identifier, user__is_active=True).first()
        if identity:
            start_password_reset(identity)
        # Same response whether or not the account exists (no enumeration).
        return Response({"detail": "If an account exists for this email, a reset code has been sent."})


class PasswordResetConfirmView(AuthThrottleMixin, APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        serializer = s.PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        kind, identifier = serializer.validated_data["identifier"]
        identity = None
        if kind == EMAIL:
            identity = AccountIdentity.objects.select_related("user").filter(email=identifier).first()
        invalid = Response(
            {"error": {"code": "invalid_code", "message": "That code is invalid or has expired."}},
            status=status.HTTP_400_BAD_REQUEST,
        )
        if identity is None:
            return invalid
        from django.contrib.auth import password_validation
        from django.core.exceptions import ValidationError

        try:
            password_validation.validate_password(serializer.validated_data["new_password"], user=identity.user)
        except ValidationError as exc:
            from rest_framework.exceptions import ValidationError as DRFValidationError

            raise DRFValidationError({"new_password": exc.messages}) from None
        if not confirm_password_reset(identity.user, serializer.validated_data["code"], serializer.validated_data["new_password"]):
            return invalid
        return Response({"detail": "Your password has been reset. Please sign in."})


class SettingsView(APIView):
    """Privacy and notification settings."""

    def get(self, request):
        return Response(self._payload(request.user))

    def patch(self, request):
        profile = get_profile(request.user)
        privacy = PrivacySettingsSerializer(profile, data=request.data.get("privacy", {}), partial=True)
        privacy.is_valid(raise_exception=True)
        from notifications.serializers import NotificationPreferenceSerializer

        prefs = NotificationPreferenceSerializer(
            get_preferences(request.user), data=request.data.get("notifications", {}), partial=True
        )
        prefs.is_valid(raise_exception=True)
        with transaction.atomic():
            privacy.save()
            prefs.save()
        return Response(self._payload(request.user))

    def _payload(self, user):
        from notifications.serializers import NotificationPreferenceSerializer

        return {
            "privacy": PrivacySettingsSerializer(get_profile(user)).data,
            "notifications": NotificationPreferenceSerializer(get_preferences(user)).data,
        }


class DeactivateView(APIView):
    """Pause the account: hidden from discovery, no new interests or messages."""

    def post(self, request):
        serializer = s.PasswordConfirmSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        profile = get_profile(request.user)
        profile.is_paused = True
        profile.save(update_fields=["is_paused", "updated_at"])
        return Response(account_payload(request.user))


class ReactivateView(APIView):
    def post(self, request):
        profile = get_profile(request.user)
        profile.is_paused = False
        profile.save(update_fields=["is_paused", "updated_at"])
        return Response(account_payload(request.user))


class DeleteAccountView(AuthThrottleMixin, APIView):
    def post(self, request):
        serializer = s.PasswordConfirmSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        delete_account(request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)
