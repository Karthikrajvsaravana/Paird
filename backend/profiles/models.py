import uuid
from datetime import date

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models import Q
from django.utils import timezone

from . import choices as c


def age_on(dob, today=None):
    if dob is None:
        return None
    today = today or timezone.localdate()
    return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


class Profile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="profile")

    # Personal
    gender = models.CharField(max_length=20, choices=c.GENDER, blank=True)
    date_of_birth = models.DateField(null=True, blank=True)
    height_cm = models.PositiveSmallIntegerField(
        null=True, blank=True, validators=[MinValueValidator(120), MaxValueValidator(230)]
    )
    marital_status = models.CharField(max_length=20, choices=c.MARITAL_STATUS, blank=True)
    has_children = models.BooleanField(null=True, blank=True)
    religion = models.CharField(max_length=20, choices=c.RELIGION, blank=True)
    community = models.CharField(max_length=60, blank=True)
    mother_tongue = models.CharField(max_length=40, blank=True)

    # Location
    city = models.CharField(max_length=80, blank=True)
    state = models.CharField(max_length=80, blank=True)
    country = models.CharField(max_length=60, blank=True)
    open_to_relocate = models.CharField(max_length=10, choices=c.RELOCATION, blank=True)

    # Education & career
    education_level = models.CharField(max_length=20, choices=c.EDUCATION_LEVEL, blank=True)
    education_field = models.CharField(max_length=80, blank=True)
    occupation = models.CharField(max_length=80, blank=True)
    employment_type = models.CharField(max_length=20, choices=c.EMPLOYMENT_TYPE, blank=True)
    annual_income = models.PositiveBigIntegerField(null=True, blank=True)
    income_currency = models.CharField(max_length=3, choices=c.CURRENCY, blank=True)

    # Family
    family_type = models.CharField(max_length=10, choices=c.FAMILY_TYPE, blank=True)
    family_values = models.CharField(max_length=12, choices=c.FAMILY_VALUES, blank=True)
    about_family = models.TextField(max_length=500, blank=True)

    # Lifestyle
    diet = models.CharField(max_length=20, choices=c.DIET, blank=True)
    smoking = models.CharField(max_length=12, choices=c.SMOKING, blank=True)
    drinking = models.CharField(max_length=12, choices=c.DRINKING, blank=True)

    # Marriage plans
    wants_children = models.CharField(max_length=10, choices=c.WANTS_CHILDREN, blank=True)
    marriage_timeline = models.CharField(max_length=20, choices=c.MARRIAGE_TIMELINE, blank=True)
    living_arrangement = models.CharField(max_length=20, choices=c.LIVING_ARRANGEMENT, blank=True)

    about_me = models.TextField(max_length=1000, blank=True)

    # Onboarding
    onboarding_step = models.PositiveSmallIntegerField(default=0)
    consent_accepted_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    # Privacy & visibility
    discoverable = models.BooleanField(default=True)
    is_paused = models.BooleanField(default=False, help_text="Account deactivated by the member.")
    photo_visibility = models.CharField(max_length=10, choices=c.AUDIENCE_EVERYONE_MATCHES, default="everyone")
    interests_from = models.CharField(max_length=10, choices=c.INTERESTS_FROM, default="everyone")
    messages_from = models.CharField(max_length=20, choices=c.MESSAGES_FROM, default="matches")
    income_visibility = models.CharField(max_length=10, choices=c.AUDIENCE_WITH_HIDDEN, default="matches")
    lifestyle_visibility = models.CharField(max_length=10, choices=c.AUDIENCE_WITH_HIDDEN, default="everyone")
    show_last_seen = models.BooleanField(default=True)

    last_active_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["completed_at", "discoverable", "is_paused"]),
            models.Index(fields=["gender", "date_of_birth"]),
            models.Index(fields=["-last_active_at"]),
        ]

    def __str__(self):
        return f"Profile<{self.user_id}>"

    @property
    def age(self):
        return age_on(self.date_of_birth)

    @property
    def is_complete(self):
        return self.completed_at is not None

    @property
    def is_visible_in_discovery(self):
        return self.is_complete and self.discoverable and not self.is_paused and self.user.is_active


class PartnerPreference(models.Model):
    """
    What the member is looking for. Gender and age range are hard filters in
    discovery; every other field is optional and contributes to the Vibe Score.
    List fields hold choice keys from profiles.choices; empty means "any".
    """

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="partner_preference")
    genders = models.JSONField(default=list, blank=True)
    age_min = models.PositiveSmallIntegerField(null=True, blank=True)
    age_max = models.PositiveSmallIntegerField(null=True, blank=True)
    height_min_cm = models.PositiveSmallIntegerField(null=True, blank=True)
    height_max_cm = models.PositiveSmallIntegerField(null=True, blank=True)
    marital_statuses = models.JSONField(default=list, blank=True)
    religions = models.JSONField(default=list, blank=True)
    countries = models.JSONField(default=list, blank=True)
    education_levels = models.JSONField(default=list, blank=True)
    employment_types = models.JSONField(default=list, blank=True)
    income_min = models.PositiveBigIntegerField(null=True, blank=True)
    income_currency = models.CharField(max_length=3, choices=c.CURRENCY, blank=True)
    requires_relocation_openness = models.BooleanField(default=False)
    wants_children = models.JSONField(default=list, blank=True)
    marriage_timelines = models.JSONField(default=list, blank=True)
    living_arrangements = models.JSONField(default=list, blank=True)
    diets = models.JSONField(default=list, blank=True)
    smoking = models.JSONField(default=list, blank=True)
    drinking = models.JSONField(default=list, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                condition=Q(age_min__isnull=True) | Q(age_max__isnull=True) | Q(age_min__lte=models.F("age_max")),
                name="pref_age_range_valid",
            ),
            models.CheckConstraint(
                condition=Q(height_min_cm__isnull=True)
                | Q(height_max_cm__isnull=True)
                | Q(height_min_cm__lte=models.F("height_max_cm")),
                name="pref_height_range_valid",
            ),
        ]


def photo_upload_path(instance, filename):
    return f"profile_photos/{instance.user_id}/{uuid.uuid4().hex}.jpg"


class Photo(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="photos")
    image = models.ImageField(upload_to=photo_upload_path)
    width = models.PositiveIntegerField(default=0)
    height = models.PositiveIntegerField(default=0)
    position = models.PositiveSmallIntegerField(default=0)
    is_primary = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-is_primary", "position", "id"]
        constraints = [
            models.UniqueConstraint(fields=["user"], condition=Q(is_primary=True), name="one_primary_photo_per_user"),
        ]


def min_birth_date(today=None):
    """Latest date of birth allowed for the configured minimum age."""
    today = today or timezone.localdate()
    years = settings.PAIRD["MIN_AGE"]
    try:
        return today.replace(year=today.year - years)
    except ValueError:  # 29 Feb
        return date(today.year - years, 2, 28)
