from django.test import TestCase
from rest_framework.test import APIClient

from core.tests.helpers import client_for, make_user


class HealthAndErrorsTests(TestCase):
    def test_health_is_public_and_reveals_no_config(self):
        response = APIClient().get("/api/v1/health/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok", "database": "ok"})

    def test_protected_endpoints_require_auth_with_error_envelope(self):
        response = APIClient().get("/api/v1/dashboard/")
        self.assertEqual(response.status_code, 401)
        self.assertIn("error", response.json())
        self.assertIn("message", response.json()["error"])

    def test_validation_error_envelope_has_fields(self):
        response = APIClient().post("/api/v1/auth/register/", {}, format="json")
        self.assertEqual(response.status_code, 400)
        body = response.json()["error"]
        self.assertEqual(body["code"], "validation_error")
        self.assertIn("identifier", body["fields"])


class DashboardTests(TestCase):
    def test_dashboard_for_new_member_has_no_invented_data(self):
        user = make_user("new@example.com", complete=False)
        response = client_for(user).get("/api/v1/dashboard/")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data["profile"]["is_complete"])
        self.assertEqual(data["counts"]["matches"], 0)
        self.assertEqual(data["counts"]["interests_received"], 0)
        self.assertEqual(data["recommendations"], [])
        self.assertEqual(data["verification_status"], "unverified")
        self.assertIn("complete_profile", [n["kind"] for n in data["notices"]])

    def test_dashboard_counts_real_interests_and_recommendations(self):
        me = make_user("me@example.com", gender="woman", looking_for=["man"])
        him = make_user("him@example.com", gender="man", looking_for=["woman"])
        client_for(him).post("/api/v1/interests/", {"receiver_id": me.id}, format="json")
        data = client_for(me).get("/api/v1/dashboard/").json()
        self.assertEqual(data["counts"]["interests_received"], 1)
        self.assertEqual(data["counts"]["unread_notifications"], 1)
        # He already sent me an interest, so he still shows (I can accept).
        self.assertEqual([r["user_id"] for r in data["recommendations"]], [him.id])


class ProductionErrorPagesTests(TestCase):
    def test_unknown_route_returns_json_404_without_debug_details(self):
        response = APIClient().get("/api/v1/definitely-not-here/")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["error"]["code"], "not_found")
