import io

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.files.base import ContentFile
from django.db.models import Q
from PIL import Image, ImageOps, UnidentifiedImageError

from .models import PartnerPreference, Photo, Profile

ONBOARDING_STEPS = [
    "basics",
    "location",
    "career",
    "family",
    "lifestyle",
    "plans",
    "about",
    "photos",
    "preferences",
    "privacy",
]

# Fields that must be present before a profile can be published.
REQUIRED_PROFILE_FIELDS = [
    "gender",
    "date_of_birth",
    "marital_status",
    "city",
    "country",
    "education_level",
    "occupation",
    "marriage_timeline",
]

# Fields that count towards the completion percentage.
COMPLETION_FIELDS = REQUIRED_PROFILE_FIELDS + [
    "height_cm",
    "mother_tongue",
    "open_to_relocate",
    "education_field",
    "employment_type",
    "family_type",
    "family_values",
    "diet",
    "smoking",
    "drinking",
    "wants_children",
    "living_arrangement",
    "about_me",
]


def get_profile(user):
    profile, _ = Profile.objects.get_or_create(user=user)
    return profile


def get_preference(user):
    preference, _ = PartnerPreference.objects.get_or_create(user=user)
    return preference


def _filled(value):
    return value not in (None, "", [])


def missing_required(profile, preference):
    missing = [field for field in REQUIRED_PROFILE_FIELDS if not _filled(getattr(profile, field))]
    if not preference.genders:
        missing.append("looking_for")
    if profile.consent_accepted_at is None:
        missing.append("consent")
    return missing


def completion_percentage(profile, photo_count=None):
    if photo_count is None:
        photo_count = Photo.objects.filter(user_id=profile.user_id).count()
    total = len(COMPLETION_FIELDS) + 1
    filled = sum(1 for field in COMPLETION_FIELDS if _filled(getattr(profile, field)))
    filled += 1 if photo_count else 0
    return round(100 * filled / total)


# ---------------------------------------------------------------------------
# Relationship & visibility
# ---------------------------------------------------------------------------

SELF = "self"
MATCH = "match"
OTHER = "other"


def relationship(viewer, target_user_id):
    from matching.services import active_match_between

    if viewer.id == target_user_id:
        return SELF
    if active_match_between(viewer.id, target_user_id):
        return MATCH
    return OTHER


def audience_allows(audience, rel):
    if rel == SELF:
        return True
    if audience == "everyone":
        return True
    if audience == "matches":
        return rel == MATCH
    return False


def can_view_profile(viewer, target_profile):
    """Server-side authorization for viewing another member's profile."""
    from matching.models import Interest
    from safety.services import is_blocked_between

    target = target_profile.user
    if target.id == viewer.id:
        return True
    if not target.is_active or target_profile.is_paused or not target_profile.is_complete:
        return False
    if is_blocked_between(viewer, target):
        return False
    if target_profile.discoverable:
        return True
    # Hidden profiles stay visible to people they already have a connection with.
    return Interest.objects.filter(
        Q(sender=viewer, receiver=target) | Q(sender=target, receiver=viewer),
        status__in=[Interest.PENDING, Interest.ACCEPTED],
    ).exists()


# ---------------------------------------------------------------------------
# Photos
# ---------------------------------------------------------------------------

ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}
MAX_DIMENSION = 2048


def process_image_upload(uploaded):
    """
    Validate and re-encode an uploaded image as JPEG. Re-encoding strips EXIF
    metadata (including GPS location) and neutralises polyglot files.
    The returned ContentFile carries `.width` and `.height` of the result.
    """
    max_bytes = settings.PHOTO_MAX_UPLOAD_BYTES
    if uploaded.size > max_bytes:
        raise ValidationError(f"Photos must be smaller than {max_bytes // (1024 * 1024)} MB.")
    try:
        probe = Image.open(uploaded)
        image_format = probe.format
        probe.verify()
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError):
        raise ValidationError("Upload a valid JPEG, PNG or WebP image.") from None
    if image_format not in ALLOWED_FORMATS:
        raise ValidationError("Upload a valid JPEG, PNG or WebP image.")

    uploaded.seek(0)
    try:
        image = Image.open(uploaded)
        if image.width * image.height > 40_000_000:
            raise ValidationError("This image is too large.")
        image = ImageOps.exif_transpose(image)
        image = image.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise ValidationError("Upload a valid JPEG, PNG or WebP image.") from None
    if min(image.size) < 200:
        raise ValidationError("Photos must be at least 200 pixels wide and tall.")
    image.thumbnail((MAX_DIMENSION, MAX_DIMENSION))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=85, optimize=True)
    content = ContentFile(buffer.getvalue(), name="photo.jpg")
    content.width, content.height = image.size
    return content


def delete_stored_file(field_file):
    if field_file and field_file.name:
        field_file.storage.delete(field_file.name)
