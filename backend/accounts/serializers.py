from django.contrib.auth import authenticate, get_user_model, password_validation
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers

from .identifiers import EMAIL, normalize_identifier
from .models import AccountIdentity

User = get_user_model()


def _identifier_field(value):
    try:
        return normalize_identifier(value)
    except DjangoValidationError as exc:
        raise serializers.ValidationError(exc.messages) from None


class RegisterSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=150, trim_whitespace=True)
    identifier = serializers.CharField(max_length=254)
    password = serializers.CharField(write_only=True, max_length=128, trim_whitespace=False)

    def validate_full_name(self, value):
        value = " ".join(value.split())
        if len(value) < 2:
            raise serializers.ValidationError("Please enter your full name.")
        return value

    def validate_identifier(self, value):
        kind, normalized = _identifier_field(value)
        lookup = {"email": normalized} if kind == EMAIL else {"phone": normalized}
        if AccountIdentity.objects.filter(**lookup).exists():
            label = "email address" if kind == EMAIL else "phone number"
            raise serializers.ValidationError(f"An account with this {label} already exists. Try signing in.")
        return kind, normalized

    def validate(self, attrs):
        kind, normalized = attrs["identifier"]
        candidate = User(first_name=attrs["full_name"][:150], email=normalized if kind == EMAIL else "")
        try:
            password_validation.validate_password(attrs["password"], user=candidate)
        except DjangoValidationError as exc:
            raise serializers.ValidationError({"password": exc.messages}) from None
        return attrs


class LoginSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=254)
    password = serializers.CharField(write_only=True, max_length=128, trim_whitespace=False)

    def validate(self, attrs):
        user = authenticate(self.context.get("request"), identifier=attrs["identifier"], password=attrs["password"])
        if user is None:
            raise serializers.ValidationError("Incorrect email/phone number or password.", code="invalid_credentials")
        attrs["user"] = user
        return attrs


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True, trim_whitespace=False)
    new_password = serializers.CharField(write_only=True, max_length=128, trim_whitespace=False)

    def validate_current_password(self, value):
        if not self.context["request"].user.check_password(value):
            raise serializers.ValidationError("Your current password is incorrect.")
        return value

    def validate_new_password(self, value):
        try:
            password_validation.validate_password(value, user=self.context["request"].user)
        except DjangoValidationError as exc:
            raise serializers.ValidationError(exc.messages) from None
        return value


class PasswordConfirmSerializer(serializers.Serializer):
    password = serializers.CharField(write_only=True, trim_whitespace=False)

    def validate_password(self, value):
        if not self.context["request"].user.check_password(value):
            raise serializers.ValidationError("Your password is incorrect.")
        return value


class PasswordResetRequestSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=254)

    def validate_identifier(self, value):
        return _identifier_field(value)


class PasswordResetConfirmSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=254)
    code = serializers.RegexField(r"^\d{6}$", error_messages={"invalid": "Enter the 6-digit code."})
    new_password = serializers.CharField(write_only=True, max_length=128, trim_whitespace=False)

    def validate_identifier(self, value):
        return _identifier_field(value)


class UpdateAccountSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=150)

    def validate_full_name(self, value):
        value = " ".join(value.split())
        if len(value) < 2:
            raise serializers.ValidationError("Please enter your full name.")
        return value
