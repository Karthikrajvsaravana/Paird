import io
from datetime import date

from django.utils import timezone
from PIL import Image
from rest_framework.test import APIClient

from accounts.services import create_account, issue_tokens
from profiles.services import get_preference, get_profile

PASSWORD = "Str0ng-Passphrase!"


def make_user(
    email,
    *,
    name="Test Member",
    gender="woman",
    looking_for=("man",),
    dob=date(1995, 5, 17),
    complete=True,
    **profile_fields,
):
    user = create_account(name, "email", email, PASSWORD)
    profile = get_profile(user)
    profile.gender = gender
    profile.date_of_birth = dob
    defaults = {
        "marital_status": "never_married",
        "city": "Chennai",
        "country": "India",
        "education_level": "bachelors",
        "occupation": "Engineer",
        "marriage_timeline": "6_to_12_months",
    }
    defaults.update(profile_fields)
    for key, value in defaults.items():
        setattr(profile, key, value)
    if complete:
        profile.consent_accepted_at = timezone.now()
        profile.completed_at = timezone.now()
        profile.last_active_at = timezone.now()
    profile.save()
    pref = get_preference(user)
    pref.genders = list(looking_for)
    pref.save()
    # Re-fetch so cached reverse relations (user.profile) reflect saved state.
    return type(user).objects.get(pk=user.pk)


def client_for(user):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(user)['access']}")
    return client


def image_file(size=(400, 400), fmt="JPEG", with_gps=False, name="photo.jpg"):
    image = Image.new("RGB", size, (200, 150, 100))
    buffer = io.BytesIO()
    kwargs = {}
    if with_gps:
        exif = Image.Exif()
        exif[0x010F] = "SecretCameraMaker"
        exif[0x8825] = {1: "N", 2: (13.0, 5.0, 0.0)}
        kwargs["exif"] = exif
    image.save(buffer, format=fmt, **kwargs)
    buffer.seek(0)
    buffer.name = name
    return buffer
