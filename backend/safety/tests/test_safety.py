from django.test import TestCase

from core.tests.helpers import client_for, make_user
from safety.models import Block, Report


class SafetyTests(TestCase):
    def setUp(self):
        self.alice = make_user("alice@example.com", gender="woman", looking_for=["man"])
        self.bob = make_user("bob@example.com", gender="man", looking_for=["woman"])
        self.a = client_for(self.alice)

    def test_block_is_idempotent_and_hides_from_discovery_both_ways(self):
        self.assertEqual(self.a.post("/api/v1/blocks/", {"user_id": self.bob.id}, format="json").status_code, 204)
        self.assertEqual(self.a.post("/api/v1/blocks/", {"user_id": self.bob.id}, format="json").status_code, 204)
        self.assertEqual(Block.objects.count(), 1)
        self.assertEqual(self.a.get("/api/v1/discover/").json()["results"], [])
        self.assertEqual(client_for(self.bob).get("/api/v1/discover/").json()["results"], [])
        self.assertEqual(self.a.get("/api/v1/blocks/").json()[0]["user_id"], self.bob.id)
        self.assertEqual(self.a.delete(f"/api/v1/blocks/{self.bob.id}/").status_code, 204)
        self.assertEqual(len(self.a.get("/api/v1/discover/").json()["results"]), 1)

    def test_cannot_block_self(self):
        self.assertEqual(self.a.post("/api/v1/blocks/", {"user_id": self.alice.id}, format="json").status_code, 400)

    def test_report_validation(self):
        bad = self.a.post("/api/v1/reports/", {"user_id": self.bob.id, "reason": "dislike"}, format="json")
        self.assertEqual(bad.status_code, 400)
        ok = self.a.post("/api/v1/reports/", {"user_id": self.bob.id, "reason": "fake_profile", "details": "x"}, format="json")
        self.assertEqual(ok.status_code, 201)
        self.assertEqual(Report.objects.get().status, "open")
