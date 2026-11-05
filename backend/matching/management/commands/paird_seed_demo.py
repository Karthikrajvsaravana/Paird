"""
Create (or remove) 20 demo members — 10 women and 10 men — for testing
matching. Emails end in @demo.paird.test and every profile is labelled as a
demo. Never run this against a production database with real members.

    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_seed_demo
    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_seed_demo --remove
"""

import io

from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone
from PIL import Image, ImageDraw, ImageFont

from accounts.models import AccountIdentity
from accounts.services import create_account, delete_account
from core.locations import canonical_state, find_country
from matching.demo_profiles import DEMO_EMAIL_DOMAIN, MEN, WOMEN, demo_email, profile_fields
from profiles.models import PartnerPreference, Photo
from profiles.services import get_preference, get_profile

DEFAULT_PASSWORD = "PairD-Demo-2026!"
COLOURS = [(201, 162, 74), (77, 182, 172), (121, 134, 203), (240, 128, 128), (129, 199, 132),
           (255, 183, 77), (149, 117, 205), (79, 195, 247), (174, 213, 129), (229, 115, 115)]


def _avatar(name, index):
    size = 600
    image = Image.new("RGB", (size, size), (18, 24, 22))
    draw = ImageDraw.Draw(image)
    colour = COLOURS[index % len(COLOURS)]
    draw.ellipse((60, 60, size - 60, size - 60), fill=colour)
    initials = "".join(part[0] for part in name.split()[:2]).upper()
    try:
        font = ImageFont.load_default(size=200)
    except TypeError:  # very old Pillow
        font = ImageFont.load_default()
    box = draw.textbbox((0, 0), initials, font=font)
    draw.text(((size - (box[2] - box[0])) / 2 - box[0], (size - (box[3] - box[1])) / 2 - box[1]), initials,
              fill=(18, 24, 22), font=font)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=88)
    return ContentFile(buffer.getvalue(), name="avatar.jpg")


class Command(BaseCommand):
    help = "Create 10 women + 10 men demo profiles for testing matching (or --remove them)."

    def add_arguments(self, parser):
        parser.add_argument("--remove", action="store_true", help="Delete all @demo.paird.test accounts.")
        parser.add_argument("--password", default=DEFAULT_PASSWORD, help="Password for every demo account.")
        parser.add_argument("--no-photos", action="store_true", help="Skip generating profile photos.")

    def handle(self, *args, **options):
        if options["remove"]:
            identities = AccountIdentity.objects.filter(email__endswith="@" + DEMO_EMAIL_DOMAIN).select_related("user")
            count = 0
            for identity in identities:
                delete_account(identity.user)
                count += 1
            self.stdout.write(self.style.SUCCESS(f"Removed {count} demo account(s)."))
            return

        people = [(p, "woman", "man") for p in WOMEN] + [(p, "man", "woman") for p in MEN]
        for person, _, _ in people:
            country = find_country(person["country"])
            if country is None or (person.get("state") and canonical_state(country, person["state"]) is None):
                raise CommandError(f"Bad location in demo data for {person['name']}")

        created = skipped = 0
        for index, (person, gender, looking_for) in enumerate(people):
            email = demo_email(person["name"])
            if AccountIdentity.objects.filter(email=email).exists():
                skipped += 1
                continue
            with transaction.atomic():
                user = create_account(person["name"], "email", email, options["password"])
                profile = get_profile(user)
                for field, value in profile_fields(person).items():
                    setattr(profile, field, value)
                profile.gender = gender
                now = timezone.now()
                profile.consent_accepted_at = profile.completed_at = profile.last_active_at = now
                profile.onboarding_step = 10
                profile.save()
                pref = get_preference(user)
                pref.genders = [looking_for]
                for field, value in person["pref"].items():
                    setattr(pref, field, value)
                pref.save()
            if not options["no_photos"]:
                content = _avatar(person["name"], index)
                photo = Photo(user=user, is_primary=True, position=1, width=600, height=600)
                photo.image.save(content.name, content, save=False)
                photo.save()
            created += 1

        self.stdout.write(self.style.SUCCESS(f"Created {created} demo account(s), {skipped} already existed."))
        self.stdout.write(f"Sign in as any of them with password: {options['password']}")
        for person in WOMEN[:2] + MEN[:2]:
            self.stdout.write(f"  e.g. {demo_email(person['name'])}")
        self.stdout.write("Remove them all later with: manage.py paird_seed_demo --remove")
        if PartnerPreference.objects.filter(user__identity__email__endswith="@" + DEMO_EMAIL_DOMAIN).count() != created + skipped:
            self.stdout.write(self.style.WARNING("Some demo accounts are missing preferences."))
