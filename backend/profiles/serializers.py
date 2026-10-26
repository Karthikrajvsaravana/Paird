from django.conf import settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import serializers

from . import choices as c
from .models import PartnerPreference, Photo, Profile, age_on, min_birth_date
from .services import (
    MATCH,
    ONBOARDING_STEPS,
    REQUIRED_PROFILE_FIELDS,
    SELF,
    audience_allows,
    completion_percentage,
    get_preference,
    missing_required,
)

TEXT_FIELDS = [
    "community",
    "mother_tongue",
    "city",
    "state",
    "country",
    "education_field",
    "occupation",
    "about_family",
    "about_me",
]

PROFILE_DETAIL_FIELDS = [
    "gender",
    "date_of_birth",
    "height_cm",
    "marital_status",
    "has_children",
    "religion",
    "community",
    "mother_tongue",
    "city",
    "state",
    "country",
    "open_to_relocate",
    "education_level",
    "education_field",
    "occupation",
    "employment_type",
    "annual_income",
    "income_currency",
    "family_type",
    "family_values",
    "about_family",
    "diet",
    "smoking",
    "drinking",
    "wants_children",
    "marriage_timeline",
    "living_arrangement",
    "about_me",
]

PRIVACY_FIELDS = [
    "discoverable",
    "photo_visibility",
    "interests_from",
    "messages_from",
    "income_visibility",
    "lifestyle_visibility",
    "show_last_seen",
]


def display_name(user):
    identity = getattr(user, "identity", None)
    full_name = (identity.full_name if identity else user.first_name) or ""
    parts = full_name.split()
    if not parts:
        return "Paird member"
    if len(parts) == 1:
        return parts[0]
    return f"{parts[0]} {parts[-1][0]}."


def photo_url(request, photo):
    path = reverse("photo-file", args=[photo.id])
    return request.build_absolute_uri(path) if request else path


class PhotoSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField()

    class Meta:
        model = Photo
        fields = ["id", "url", "width", "height", "position", "is_primary", "created_at"]
        read_only_fields = fields

    def get_url(self, photo):
        return photo_url(self.context.get("request"), photo)


class OwnProfileSerializer(serializers.ModelSerializer):
    full_name = serializers.SerializerMethodField()
    age = serializers.SerializerMethodField()
    is_complete = serializers.SerializerMethodField()
    completion = serializers.SerializerMethodField()
    missing_required = serializers.SerializerMethodField()
    onboarding_steps = serializers.SerializerMethodField()
    photos = serializers.SerializerMethodField()
    accept_consent = serializers.BooleanField(write_only=True, required=False)

    class Meta:
        model = Profile
        fields = (
            ["full_name", "age"]
            + PROFILE_DETAIL_FIELDS
            + PRIVACY_FIELDS
            + [
                "onboarding_step",
                "onboarding_steps",
                "consent_accepted_at",
                "accept_consent",
                "completed_at",
                "is_complete",
                "is_paused",
                "completion",
                "missing_required",
                "photos",
                "updated_at",
            ]
        )
        read_only_fields = ["consent_accepted_at", "completed_at", "is_paused", "updated_at"]

    def get_full_name(self, profile):
        identity = getattr(profile.user, "identity", None)
        return identity.full_name if identity else profile.user.first_name

    def get_age(self, profile):
        return profile.age

    def get_is_complete(self, profile):
        return profile.is_complete

    def get_completion(self, profile):
        return completion_percentage(profile)

    def get_missing_required(self, profile):
        return missing_required(profile, get_preference(profile.user))

    def get_onboarding_steps(self, profile):
        return ONBOARDING_STEPS

    def get_photos(self, profile):
        photos = Photo.objects.filter(user_id=profile.user_id)
        return PhotoSerializer(photos, many=True, context=self.context).data

    def validate_date_of_birth(self, value):
        if value is None:
            return value
        if value > timezone.localdate():
            raise serializers.ValidationError("Date of birth cannot be in the future.")
        if value > min_birth_date():
            raise serializers.ValidationError(f"You must be at least {settings.PAIRD['MIN_AGE']} years old to use Paird.")
        if age_on(value) > settings.PAIRD["MAX_AGE"]:
            raise serializers.ValidationError("Enter a valid date of birth.")
        return value

    def validate_onboarding_step(self, value):
        if value > len(ONBOARDING_STEPS):
            raise serializers.ValidationError("Invalid onboarding step.")
        return value

    def validate(self, attrs):
        for field in TEXT_FIELDS:
            if field in attrs and isinstance(attrs[field], str):
                attrs[field] = " ".join(attrs[field].split()) if field not in ("about_me", "about_family") else attrs[field].strip()

        instance = self.instance
        income = attrs.get("annual_income", getattr(instance, "annual_income", None))
        currency = attrs.get("income_currency", getattr(instance, "income_currency", ""))
        if income is not None and not currency:
            raise serializers.ValidationError({"income_currency": "Select the currency for your income."})
        if income is not None and income > 10**12:
            raise serializers.ValidationError({"annual_income": "Enter a realistic annual income."})

        if instance is not None and instance.is_complete:
            for field in REQUIRED_PROFILE_FIELDS:
                if field in attrs and attrs[field] in (None, ""):
                    raise serializers.ValidationError({field: "This field is required for a published profile."})

        if attrs.get("accept_consent") is False:
            raise serializers.ValidationError({"accept_consent": "Consent cannot be withdrawn here. Deactivate or delete your account instead."})
        return attrs

    def update(self, instance, validated_data):
        if validated_data.pop("accept_consent", False) and instance.consent_accepted_at is None:
            instance.consent_accepted_at = timezone.now()
        return super().update(instance, validated_data)


class PrivacySettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = Profile
        fields = PRIVACY_FIELDS


def _choice_list_field(choice_set):
    return serializers.ListField(
        child=serializers.ChoiceField(choices=choice_set), required=False, allow_empty=True, max_length=len(choice_set)
    )


class PartnerPreferenceSerializer(serializers.ModelSerializer):
    genders = _choice_list_field(c.GENDER)
    marital_statuses = _choice_list_field(c.MARITAL_STATUS)
    religions = _choice_list_field(c.RELIGION)
    education_levels = _choice_list_field(c.EDUCATION_LEVEL)
    employment_types = _choice_list_field(c.EMPLOYMENT_TYPE)
    wants_children = _choice_list_field(c.WANTS_CHILDREN)
    marriage_timelines = _choice_list_field(c.MARRIAGE_TIMELINE)
    living_arrangements = _choice_list_field(c.LIVING_ARRANGEMENT)
    diets = _choice_list_field(c.DIET)
    smoking = _choice_list_field(c.SMOKING)
    drinking = _choice_list_field(c.DRINKING)
    countries = serializers.ListField(
        child=serializers.CharField(max_length=60), required=False, allow_empty=True, max_length=20
    )
    age_min = serializers.IntegerField(required=False, allow_null=True, min_value=18, max_value=100)
    age_max = serializers.IntegerField(required=False, allow_null=True, min_value=18, max_value=100)
    height_min_cm = serializers.IntegerField(required=False, allow_null=True, min_value=120, max_value=230)
    height_max_cm = serializers.IntegerField(required=False, allow_null=True, min_value=120, max_value=230)
    income_min = serializers.IntegerField(required=False, allow_null=True, min_value=0, max_value=10**12)

    class Meta:
        model = PartnerPreference
        fields = [
            "genders",
            "age_min",
            "age_max",
            "height_min_cm",
            "height_max_cm",
            "marital_statuses",
            "religions",
            "countries",
            "education_levels",
            "employment_types",
            "income_min",
            "income_currency",
            "requires_relocation_openness",
            "wants_children",
            "marriage_timelines",
            "living_arrangements",
            "diets",
            "smoking",
            "drinking",
            "updated_at",
        ]
        read_only_fields = ["updated_at"]

    def validate_age_min(self, value):
        if value is not None and value < settings.PAIRD["MIN_AGE"]:
            raise serializers.ValidationError(f"Minimum age is {settings.PAIRD['MIN_AGE']}.")
        return value

    def validate(self, attrs):
        for field, value in list(attrs.items()):
            if isinstance(value, list):
                seen = []
                for item in value:
                    item = " ".join(item.split()) if isinstance(item, str) else item
                    if item and item not in seen:
                        seen.append(item)
                attrs[field] = seen

        def current(name):
            return attrs.get(name, getattr(self.instance, name, None))

        if current("age_min") is not None and current("age_max") is not None and current("age_min") > current("age_max"):
            raise serializers.ValidationError({"age_max": "Maximum age must be greater than or equal to minimum age."})
        if (
            current("height_min_cm") is not None
            and current("height_max_cm") is not None
            and current("height_min_cm") > current("height_max_cm")
        ):
            raise serializers.ValidationError({"height_max_cm": "Maximum height must be greater than minimum height."})
        if current("income_min") is not None and not current("income_currency"):
            raise serializers.ValidationError({"income_currency": "Select a currency for the minimum income."})
        return attrs


def public_profile(profile, *, viewer, request, rel, connection=None, vibe=None, verified=False):
    """
    Representation of another member's profile, filtered by their privacy
    settings and the viewer's relationship to them. Never includes contact
    details, full surname, exact date of birth or hidden fields.
    """
    lifestyle_visible = audience_allows(profile.lifestyle_visibility, rel)
    income_visible = audience_allows(profile.income_visibility, rel)
    photos_visible = audience_allows(profile.photo_visibility, rel)
    photos = list(Photo.objects.filter(user_id=profile.user_id)) if photos_visible else []
    photo_count = len(photos) if photos_visible else Photo.objects.filter(user_id=profile.user_id).count()

    viewer_profile = getattr(viewer, "profile", None)
    show_last_seen = (
        rel == SELF
        or (profile.show_last_seen and viewer_profile is not None and viewer_profile.show_last_seen)
    )

    data = {
        "user_id": profile.user_id,
        "display_name": display_name(profile.user),
        "age": profile.age,
        "gender": profile.gender,
        "height_cm": profile.height_cm,
        "marital_status": profile.marital_status,
        "has_children": profile.has_children,
        "religion": profile.religion,
        "community": profile.community,
        "mother_tongue": profile.mother_tongue,
        "city": profile.city,
        "state": profile.state,
        "country": profile.country,
        "open_to_relocate": profile.open_to_relocate,
        "education_level": profile.education_level,
        "education_field": profile.education_field,
        "occupation": profile.occupation,
        "employment_type": profile.employment_type,
        "family_type": profile.family_type,
        "family_values": profile.family_values,
        "about_family": profile.about_family,
        "wants_children": profile.wants_children,
        "marriage_timeline": profile.marriage_timeline,
        "living_arrangement": profile.living_arrangement,
        "about_me": profile.about_me,
        "is_verified": verified,
        "income": (
            {"amount": profile.annual_income, "currency": profile.income_currency}
            if income_visible and profile.annual_income is not None
            else None
        ),
        "income_hidden": not income_visible,
        "lifestyle": (
            {"diet": profile.diet, "smoking": profile.smoking, "drinking": profile.drinking}
            if lifestyle_visible
            else None
        ),
        "lifestyle_hidden": not lifestyle_visible,
        "photos": [{"id": photo.id, "url": photo_url(request, photo), "is_primary": photo.is_primary} for photo in photos],
        "photos_hidden": not photos_visible,
        "photo_count": photo_count,
        "last_active_at": profile.last_active_at if show_last_seen else None,
        "is_match": rel == MATCH,
    }
    if connection is not None:
        data["connection"] = connection
    if vibe is not None:
        data["vibe"] = vibe
    return data


def member_card(profile, *, viewer, request, rel, verified=False, vibe=None, connection=None):
    """Compact representation for lists (discover, interests, matches, chats)."""
    photo = None
    if audience_allows(profile.photo_visibility, rel):
        primary = Photo.objects.filter(user_id=profile.user_id).first()
        if primary:
            photo = photo_url(request, primary)
    data = {
        "user_id": profile.user_id,
        "display_name": display_name(profile.user),
        "age": profile.age,
        "city": profile.city,
        "country": profile.country,
        "occupation": profile.occupation,
        "education_level": profile.education_level,
        "religion": profile.religion,
        "marriage_timeline": profile.marriage_timeline,
        "photo_url": photo,
        "photos_hidden": not audience_allows(profile.photo_visibility, rel),
        "is_verified": verified,
    }
    if vibe is not None:
        data["vibe"] = vibe
    if connection is not None:
        data["connection"] = connection
    return data
