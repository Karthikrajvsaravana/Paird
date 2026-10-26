import re

from django.contrib.auth import get_user_model
from django.core import mail
from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import AccountIdentity
from core.tests.helpers import PASSWORD, client_for, make_user, image_file
from profiles.models import Photo

User = get_user_model()


class RegistrationTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def register(self, **data):
        payload = {"full_name": "Asha Raman", "identifier": "Asha@Example.com", "password": PASSWORD}
        payload.update(data)
        return self.client.post("/api/v1/auth/register/", payload, format="json")

    def test_register_with_email_returns_tokens_and_normalises(self):
        response = self.register()
        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertIn("access", body["tokens"])
        self.assertIn("refresh", body["tokens"])
        self.assertEqual(body["user"]["email"], "asha@example.com")
        self.assertFalse(body["user"]["profile_complete"])
        identity = AccountIdentity.objects.get(email="asha@example.com")
        self.assertTrue(identity.user.check_password(PASSWORD))
        self.assertNotIn(PASSWORD, str(body))

    def test_register_with_phone(self):
        response = self.register(identifier="+91 98765-43210")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["user"]["phone"], "+919876543210")

    def test_duplicate_identifier_rejected(self):
        self.register()
        response = self.register(identifier="asha@example.com ")
        self.assertEqual(response.status_code, 400)
        self.assertIn("identifier", response.json()["error"]["fields"])

    def test_weak_password_rejected(self):
        response = self.register(password="123456")
        self.assertEqual(response.status_code, 400)
        self.assertIn("password", response.json()["error"]["fields"])

    def test_invalid_identifier_rejected(self):
        for value in ["not-an-email", "12345", "9876543210"]:
            response = self.register(identifier=value)
            self.assertEqual(response.status_code, 400, value)

    def test_password_never_returned(self):
        response = self.register()
        self.assertNotIn("password", response.json()["user"])


class LoginTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.client.post(
            "/api/v1/auth/register/",
            {"full_name": "Ravi Kumar", "identifier": "+14155550123", "password": PASSWORD},
            format="json",
        )
        self.client.post(
            "/api/v1/auth/register/",
            {"full_name": "Meera Iyer", "identifier": "meera@example.com", "password": PASSWORD},
            format="json",
        )

    def login(self, identifier, password=PASSWORD):
        return self.client.post("/api/v1/auth/login/", {"identifier": identifier, "password": password}, format="json")

    def test_login_with_email_case_insensitive(self):
        response = self.login("MEERA@example.com")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["user"]["full_name"], "Meera Iyer")

    def test_login_with_formatted_phone(self):
        self.assertEqual(self.login("+1 (415) 555-0123").status_code, 200)

    def test_invalid_credentials_generic_message(self):
        wrong = self.login("meera@example.com", "wrong-password")
        unknown = self.login("nobody@example.com")
        self.assertEqual(wrong.status_code, 400)
        self.assertEqual(unknown.status_code, 400)
        self.assertEqual(wrong.json()["error"]["message"], unknown.json()["error"]["message"])

    def test_inactive_user_cannot_login(self):
        User.objects.filter(identity__email="meera@example.com").update(is_active=False)
        self.assertEqual(self.login("meera@example.com").status_code, 400)


class SessionTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        response = self.client.post(
            "/api/v1/auth/register/",
            {"full_name": "Session User", "identifier": "session@example.com", "password": PASSWORD},
            format="json",
        )
        self.tokens = response.json()["tokens"]

    def test_me_requires_valid_token(self):
        self.assertEqual(self.client.get("/api/v1/auth/me/").status_code, 401)
        self.client.credentials(HTTP_AUTHORIZATION="Bearer not-a-token")
        self.assertEqual(self.client.get("/api/v1/auth/me/").status_code, 401)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.tokens['access']}")
        response = self.client.get("/api/v1/auth/me/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["email"], "session@example.com")

    def test_update_full_name(self):
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.tokens['access']}")
        response = self.client.patch("/api/v1/auth/me/", {"full_name": "  Renamed   Person "}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["full_name"], "Renamed Person")
        self.assertEqual(self.client.patch("/api/v1/auth/me/", {"full_name": " "}, format="json").status_code, 400)

    def test_refresh_rotates_and_old_refresh_is_revoked(self):
        first = self.client.post("/api/v1/auth/refresh/", {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(first.status_code, 200)
        self.assertIn("refresh", first.json())
        replay = self.client.post("/api/v1/auth/refresh/", {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(replay.status_code, 401)

    def test_logout_revokes_refresh_token(self):
        response = self.client.post("/api/v1/auth/logout/", {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(response.status_code, 204)
        after = self.client.post("/api/v1/auth/refresh/", {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(after.status_code, 401)

    def test_refresh_rejected_for_deactivated_django_user(self):
        User.objects.filter(identity__email="session@example.com").update(is_active=False)
        response = self.client.post("/api/v1/auth/refresh/", {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(response.status_code, 401)

    def test_change_password_revokes_existing_sessions(self):
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.tokens['access']}")
        response = self.client.post(
            "/api/v1/auth/change-password/",
            {"current_password": PASSWORD, "new_password": "An0ther-Strong-One!"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        old = self.client.post("/api/v1/auth/refresh/", {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(old.status_code, 401)

    def test_change_password_requires_current_password(self):
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {self.tokens['access']}")
        response = self.client.post(
            "/api/v1/auth/change-password/",
            {"current_password": "wrong", "new_password": "An0ther-Strong-One!"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)


class PasswordResetTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = make_user("reset@example.com", complete=False)

    def test_reset_flow_with_email_code(self):
        response = self.client.post("/api/v1/auth/password-reset/", {"identifier": "reset@example.com"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(mail.outbox), 1)
        code = re.search(r"\b(\d{6})\b", mail.outbox[0].body).group(1)
        wrong = self.client.post(
            "/api/v1/auth/password-reset/confirm/",
            {"identifier": "reset@example.com", "code": "000000" if code != "000000" else "111111", "new_password": "Brand-New-Pass-9"},
            format="json",
        )
        self.assertEqual(wrong.status_code, 400)
        ok = self.client.post(
            "/api/v1/auth/password-reset/confirm/",
            {"identifier": "reset@example.com", "code": code, "new_password": "Brand-New-Pass-9"},
            format="json",
        )
        self.assertEqual(ok.status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("Brand-New-Pass-9"))
        reuse = self.client.post(
            "/api/v1/auth/password-reset/confirm/",
            {"identifier": "reset@example.com", "code": code, "new_password": "Another-Pass-10"},
            format="json",
        )
        self.assertEqual(reuse.status_code, 400)

    def test_unknown_email_gets_same_response_and_no_email(self):
        response = self.client.post("/api/v1/auth/password-reset/", {"identifier": "ghost@example.com"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(mail.outbox), 0)

    def test_phone_reset_reports_unavailable(self):
        response = self.client.post("/api/v1/auth/password-reset/", {"identifier": "+919876543210"}, format="json")
        self.assertEqual(response.status_code, 503)


class AccountLifecycleTests(TestCase):
    def test_delete_requires_password_and_removes_data(self):
        user = make_user("delete@example.com")
        client = client_for(user)
        client.post("/api/v1/photos/", {"image": image_file()}, format="multipart")
        photo = Photo.objects.get(user=user)
        path = photo.image.path
        self.assertEqual(client.post("/api/v1/account/delete/", {"password": "nope"}, format="json").status_code, 400)
        self.assertEqual(client.post("/api/v1/account/delete/", {"password": PASSWORD}, format="json").status_code, 204)
        self.assertFalse(User.objects.filter(pk=user.pk).exists())
        self.assertFalse(AccountIdentity.objects.filter(email="delete@example.com").exists())
        import os

        self.assertFalse(os.path.exists(path))

    def test_deactivate_and_reactivate(self):
        user = make_user("pause@example.com")
        client = client_for(user)
        response = client.post("/api/v1/account/deactivate/", {"password": PASSWORD}, format="json")
        self.assertTrue(response.json()["is_paused"])
        response = client.post("/api/v1/account/reactivate/", {}, format="json")
        self.assertFalse(response.json()["is_paused"])

    def test_settings_update_privacy_and_notifications(self):
        user = make_user("settings@example.com")
        client = client_for(user)
        response = client.patch(
            "/api/v1/settings/",
            {"privacy": {"photo_visibility": "matches", "show_last_seen": False}, "notifications": {"messages": False}},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["privacy"]["photo_visibility"], "matches")
        self.assertFalse(response.json()["notifications"]["messages"])
        bad = client.patch("/api/v1/settings/", {"privacy": {"photo_visibility": "aliens"}}, format="json")
        self.assertEqual(bad.status_code, 400)
