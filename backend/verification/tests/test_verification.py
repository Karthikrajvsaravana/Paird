import os

from django.contrib.admin.sites import AdminSite
from django.contrib.auth import get_user_model
from django.contrib.messages.storage.fallback import FallbackStorage
from django.test import RequestFactory, TestCase

from core.tests.helpers import client_for, image_file, make_user
from verification.admin import VerificationRequestAdmin, approve
from verification.models import VerificationRequest


class VerificationTests(TestCase):
    def setUp(self):
        self.user = make_user("verify@example.com")
        self.client = client_for(self.user)

    def test_default_status_unverified(self):
        data = self.client.get("/api/v1/verification/").json()
        self.assertEqual(data["status"], "unverified")
        self.assertEqual(data["method"], "photo_review")

    def test_requires_profile_photo(self):
        response = self.client.post("/api/v1/verification/", {"selfie": image_file()}, format="multipart")
        self.assertEqual(response.status_code, 400)

    def test_submission_is_pending_until_staff_approve_and_selfie_deleted(self):
        self.client.post("/api/v1/photos/", {"image": image_file()}, format="multipart")
        response = self.client.post("/api/v1/verification/", {"selfie": image_file()}, format="multipart")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["status"], "pending")
        self.assertFalse(response.json()["can_submit"])
        again = self.client.post("/api/v1/verification/", {"selfie": image_file()}, format="multipart")
        self.assertEqual(again.status_code, 400)

        request_obj = VerificationRequest.objects.get()
        selfie_path = request_obj.selfie.path
        self.assertTrue(os.path.exists(selfie_path))

        staff = get_user_model().objects.create_user("staff", password="x", is_staff=True)
        http_request = RequestFactory().post("/admin/")
        http_request.user = staff
        http_request.session = {}
        http_request._messages = FallbackStorage(http_request)
        approve(VerificationRequestAdmin(VerificationRequest, AdminSite()), http_request, VerificationRequest.objects.all())

        self.assertEqual(self.client.get("/api/v1/verification/").json()["status"], "verified")
        self.assertFalse(os.path.exists(selfie_path))
        self.assertEqual(self.client.get("/api/v1/dashboard/").json()["verification_status"], "verified")

    def test_client_cannot_set_verified(self):
        self.client.patch("/api/v1/profile/me/", {"is_verified": True}, format="json")
        self.assertEqual(self.client.get("/api/v1/verification/").json()["status"], "unverified")
