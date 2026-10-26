from datetime import timedelta

from django.test import TestCase
from django.utils import timezone
from PIL import Image

from core.tests.helpers import client_for, image_file, make_user
from matching.models import Match
from messaging.models import Conversation
from profiles.models import Photo
from safety.models import Block


def make_match(a, b):
    low, high = Match.ordered(a.id, b.id)
    match = Match.objects.create(user_a_id=low, user_b_id=high)
    Conversation.objects.create(match=match)
    return match


class OnboardingTests(TestCase):
    def setUp(self):
        self.user = make_user("onboard@example.com", complete=False, gender="", city="", marital_status="")
        self.client = client_for(self.user)

    def test_partial_updates_are_saved_and_resumable(self):
        response = self.client.patch("/api/v1/profile/me/", {"gender": "man", "onboarding_step": 1}, format="json")
        self.assertEqual(response.status_code, 200)
        again = self.client.get("/api/v1/profile/me/").json()
        self.assertEqual(again["gender"], "man")
        self.assertEqual(again["onboarding_step"], 1)

    def test_underage_and_future_dob_rejected(self):
        too_young = timezone.localdate() - timedelta(days=365 * 17)
        response = self.client.patch("/api/v1/profile/me/", {"date_of_birth": too_young.isoformat()}, format="json")
        self.assertEqual(response.status_code, 400)
        future = timezone.localdate() + timedelta(days=3)
        response = self.client.patch("/api/v1/profile/me/", {"date_of_birth": future.isoformat()}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_invalid_choice_rejected(self):
        response = self.client.patch("/api/v1/profile/me/", {"religion": "pastafarian"}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_income_requires_currency(self):
        response = self.client.patch("/api/v1/profile/me/", {"annual_income": 1200000}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_publish_requires_required_fields_and_consent(self):
        response = self.client.post("/api/v1/profile/me/publish/", {}, format="json")
        self.assertEqual(response.status_code, 400)
        self.client.patch(
            "/api/v1/profile/me/",
            {"gender": "man", "city": "Pune", "marital_status": "never_married", "accept_consent": True},
            format="json",
        )
        response = self.client.post("/api/v1/profile/me/publish/", {}, format="json")
        self.assertEqual(response.status_code, 200, response.json())
        self.assertTrue(response.json()["is_complete"])

    def test_cannot_blank_required_field_after_publish(self):
        self.client.patch(
            "/api/v1/profile/me/",
            {"gender": "man", "city": "Pune", "marital_status": "never_married", "accept_consent": True},
            format="json",
        )
        self.client.post("/api/v1/profile/me/publish/", {}, format="json")
        response = self.client.patch("/api/v1/profile/me/", {"city": ""}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_completion_percentage_increases(self):
        before = self.client.get("/api/v1/profile/me/").json()["completion"]
        self.client.patch("/api/v1/profile/me/", {"about_me": "Hello", "diet": "vegetarian"}, format="json")
        after = self.client.get("/api/v1/profile/me/").json()["completion"]
        self.assertGreater(after, before)


class PreferenceTests(TestCase):
    def test_preferences_validated_and_saved(self):
        user = make_user("pref@example.com")
        client = client_for(user)
        response = client.put(
            "/api/v1/preferences/",
            {"genders": ["man"], "age_min": 25, "age_max": 32, "religions": ["hindu", "hindu"], "countries": [" India "]},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.json())
        self.assertEqual(response.json()["religions"], ["hindu"])
        self.assertEqual(response.json()["countries"], ["India"])
        self.assertEqual(client.patch("/api/v1/preferences/", {"age_min": 40, "age_max": 30}, format="json").status_code, 400)
        self.assertEqual(client.patch("/api/v1/preferences/", {"age_min": 16}, format="json").status_code, 400)
        self.assertEqual(client.patch("/api/v1/preferences/", {"diets": ["meatballs"]}, format="json").status_code, 400)


class PhotoTests(TestCase):
    def setUp(self):
        self.user = make_user("photo@example.com")
        self.client = client_for(self.user)

    def test_upload_strips_exif_and_sets_primary(self):
        response = self.client.post("/api/v1/photos/", {"image": image_file(with_gps=True)}, format="multipart")
        self.assertEqual(response.status_code, 201, response.json())
        self.assertTrue(response.json()["is_primary"])
        photo = Photo.objects.get(user=self.user)
        self.assertEqual((photo.width, photo.height), (400, 400))
        with Image.open(photo.image.path) as stored:
            self.assertEqual(dict(stored.getexif()), {})

    def test_dark_low_detail_image_gets_dimensions(self):
        import io

        buffer = io.BytesIO()
        Image.new("RGB", (400, 400)).save(buffer, "JPEG")
        buffer.seek(0)
        buffer.name = "black.jpg"
        response = self.client.post("/api/v1/photos/", {"image": buffer}, format="multipart")
        self.assertEqual(response.status_code, 201, response.json())
        self.assertEqual((response.json()["width"], response.json()["height"]), (400, 400))

    def test_rejects_non_images_and_tiny_images(self):
        import io

        fake = io.BytesIO(b"<?php echo 'hi'; ?>")
        fake.name = "evil.jpg"
        self.assertEqual(self.client.post("/api/v1/photos/", {"image": fake}, format="multipart").status_code, 400)
        tiny = image_file(size=(50, 50))
        self.assertEqual(self.client.post("/api/v1/photos/", {"image": tiny}, format="multipart").status_code, 400)

    def test_rejects_oversized_upload(self):
        with self.settings(PHOTO_MAX_UPLOAD_BYTES=1000):
            response = self.client.post("/api/v1/photos/", {"image": image_file()}, format="multipart")
        self.assertEqual(response.status_code, 400)

    def test_photo_limit(self):
        with self.settings(PHOTO_MAX_PER_PROFILE=2):
            for _ in range(2):
                self.assertEqual(self.client.post("/api/v1/photos/", {"image": image_file()}, format="multipart").status_code, 201)
            self.assertEqual(self.client.post("/api/v1/photos/", {"image": image_file()}, format="multipart").status_code, 400)

    def test_delete_primary_promotes_next(self):
        first = self.client.post("/api/v1/photos/", {"image": image_file()}, format="multipart").json()
        second = self.client.post("/api/v1/photos/", {"image": image_file()}, format="multipart").json()
        self.assertEqual(self.client.delete(f"/api/v1/photos/{first['id']}/").status_code, 204)
        self.assertTrue(Photo.objects.get(pk=second["id"]).is_primary)

    def test_cannot_modify_someone_elses_photo(self):
        other = make_user("other-photo@example.com")
        photo = client_for(other).post("/api/v1/photos/", {"image": image_file()}, format="multipart").json()
        self.assertEqual(self.client.delete(f"/api/v1/photos/{photo['id']}/").status_code, 404)
        self.assertEqual(self.client.patch(f"/api/v1/photos/{photo['id']}/", {"is_primary": True}, format="json").status_code, 404)


class ProfilePrivacyTests(TestCase):
    def setUp(self):
        self.viewer = make_user("viewer@example.com", gender="man", looking_for=["woman"])
        self.target = make_user(
            "target@example.com",
            name="Priya Sharma",
            gender="woman",
            looking_for=["man"],
            annual_income=1500000,
            income_currency="INR",
            diet="vegetarian",
        )
        self.target_client = client_for(self.target)
        self.photo = self.target_client.post("/api/v1/photos/", {"image": image_file()}, format="multipart").json()
        self.client = client_for(self.viewer)

    def get(self):
        return self.client.get(f"/api/v1/members/{self.target.id}/")

    def test_public_profile_never_includes_contact_details_or_dob(self):
        data = self.get().json()
        text = str(data)
        self.assertNotIn("target@example.com", text)
        self.assertNotIn("date_of_birth", data)
        self.assertNotIn("Sharma", text)
        self.assertEqual(data["display_name"], "Priya S.")

    def test_income_hidden_from_non_matches_by_default(self):
        data = self.get().json()
        self.assertIsNone(data["income"])
        self.assertTrue(data["income_hidden"])
        make_match(self.viewer, self.target)
        data = self.get().json()
        self.assertEqual(data["income"], {"amount": 1500000, "currency": "INR"})

    def test_lifestyle_visibility(self):
        self.target.profile.lifestyle_visibility = "hidden"
        self.target.profile.save()
        data = self.get().json()
        self.assertIsNone(data["lifestyle"])

    def test_photo_visibility_matches_only_enforced_on_file(self):
        self.assertEqual(self.client.get(f"/api/v1/photos/{self.photo['id']}/file/").status_code, 200)
        self.target.profile.photo_visibility = "matches"
        self.target.profile.save()
        data = self.get().json()
        self.assertEqual(data["photos"], [])
        self.assertTrue(data["photos_hidden"])
        self.assertEqual(data["photo_count"], 1)
        self.assertEqual(self.client.get(f"/api/v1/photos/{self.photo['id']}/file/").status_code, 404)
        make_match(self.viewer, self.target)
        self.assertEqual(self.client.get(f"/api/v1/photos/{self.photo['id']}/file/").status_code, 200)

    def test_blocked_paused_incomplete_and_hidden_profiles_not_viewable(self):
        Block.objects.create(blocker=self.target, blocked=self.viewer)
        self.assertEqual(self.get().status_code, 404)
        self.assertEqual(self.client.get(f"/api/v1/photos/{self.photo['id']}/file/").status_code, 404)
        Block.objects.all().delete()

        self.target.profile.is_paused = True
        self.target.profile.save()
        self.assertEqual(self.get().status_code, 404)
        self.target.profile.is_paused = False
        self.target.profile.discoverable = False
        self.target.profile.save()
        self.assertEqual(self.get().status_code, 404)

        incomplete = make_user("incomplete@example.com", complete=False)
        self.assertEqual(self.client.get(f"/api/v1/members/{incomplete.id}/").status_code, 404)

    def test_unauthenticated_cannot_view_profiles_or_photos(self):
        from rest_framework.test import APIClient

        self.assertEqual(APIClient().get(f"/api/v1/members/{self.target.id}/").status_code, 401)
        self.assertEqual(APIClient().get(f"/api/v1/photos/{self.photo['id']}/file/").status_code, 401)

    def test_last_seen_is_reciprocal(self):
        self.assertIsNotNone(self.get().json()["last_active_at"])
        self.viewer.profile.show_last_seen = False
        self.viewer.profile.save()
        self.assertIsNone(self.get().json()["last_active_at"])
