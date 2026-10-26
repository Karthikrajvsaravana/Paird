from django.test import TestCase

from core.tests.helpers import client_for, make_user
from messaging.models import Conversation
from verification.models import VerificationRequest


class MessagingTests(TestCase):
    def setUp(self):
        self.alice = make_user("alice@example.com", gender="woman", looking_for=["man"])
        self.bob = make_user("bob@example.com", gender="man", looking_for=["woman"])
        self.eve = make_user("eve@example.com", gender="woman", looking_for=["man"])
        self.a, self.b, self.e = client_for(self.alice), client_for(self.bob), client_for(self.eve)
        interest_id = self.a.post("/api/v1/interests/", {"receiver_id": self.bob.id}, format="json").json()["interest"]["id"]
        self.conversation_id = self.b.post(f"/api/v1/interests/{interest_id}/accept/").json()["match"]["conversation_id"]
        self.url = f"/api/v1/conversations/{self.conversation_id}/messages/"

    def test_send_receive_unread_and_read_status(self):
        sent = self.a.post(self.url, {"body": "  Hi Bob!  "}, format="json")
        self.assertEqual(sent.status_code, 201)
        self.assertEqual(sent.json()["body"], "Hi Bob!")
        convs = self.b.get("/api/v1/conversations/").json()["results"]
        self.assertEqual(convs[0]["unread_count"], 1)
        self.assertEqual(self.b.get("/api/v1/dashboard/").json()["counts"]["unread_messages"], 1)
        history = self.b.get(self.url).json()
        self.assertEqual(history["results"][0]["body"], "Hi Bob!")
        self.assertEqual(self.b.get("/api/v1/conversations/").json()["results"][0]["unread_count"], 0)
        mine = self.a.get(self.url).json()["results"][0]
        self.assertTrue(mine["is_mine"])
        self.assertTrue(mine["is_read"])

    def test_non_participants_cannot_read_or_send(self):
        self.a.post(self.url, {"body": "secret"}, format="json")
        self.assertEqual(self.e.get(self.url).status_code, 404)
        self.assertEqual(self.e.post(self.url, {"body": "hi"}, format="json").status_code, 404)
        self.assertEqual(self.e.get("/api/v1/conversations/").json()["results"], [])

    def test_validation(self):
        self.assertEqual(self.a.post(self.url, {"body": "   "}, format="json").status_code, 400)
        self.assertEqual(self.a.post(self.url, {"body": "x" * 2001}, format="json").status_code, 400)

    def test_pagination_and_polling(self):
        for i in range(35):
            self.a.post(self.url, {"body": f"m{i}"}, format="json")
        first = self.b.get(self.url).json()
        self.assertEqual(len(first["results"]), 30)
        self.assertTrue(first["has_more"])
        oldest = min(m["id"] for m in first["results"])
        older = self.b.get(f"{self.url}?before={oldest}").json()
        self.assertEqual(len(older["results"]), 5)
        self.assertFalse(older["has_more"])
        newest = max(m["id"] for m in first["results"])
        self.a.post(self.url, {"body": "new one"}, format="json")
        new = self.b.get(f"{self.url}?after={newest}").json()
        self.assertEqual([m["body"] for m in new["results"]], ["new one"])

    def test_cannot_send_after_match_ended_or_block(self):
        conversation = Conversation.objects.get(pk=self.conversation_id)
        self.a.post(f"/api/v1/matches/{conversation.match_id}/end/")
        response = self.b.post(self.url, {"body": "still there?"}, format="json")
        self.assertEqual(response.status_code, 403)
        self.b.post("/api/v1/blocks/", {"user_id": self.alice.id}, format="json")
        self.assertEqual(self.a.get(self.url).status_code, 404)
        self.assertEqual(self.a.get("/api/v1/conversations/").json()["results"], [])

    def test_messages_from_verified_matches_only(self):
        self.bob.profile.messages_from = "verified_matches"
        self.bob.profile.save()
        self.assertEqual(self.a.post(self.url, {"body": "hi"}, format="json").status_code, 403)
        self.assertFalse(self.a.get(self.url).json()["conversation"]["can_send"])
        VerificationRequest.objects.create(user=self.alice, status="approved")
        self.assertEqual(self.a.post(self.url, {"body": "hi"}, format="json").status_code, 201)

    def test_report_message(self):
        message_id = self.b.post(self.url, {"body": "rude"}, format="json").json()["id"]
        response = self.a.post(
            "/api/v1/reports/",
            {"user_id": self.bob.id, "reason": "harassment", "message_id": message_id, "block": True},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.a.get("/api/v1/conversations/").json()["results"], [])
        # Eve cannot attach a message she never saw
        response = self.e.post(
            "/api/v1/reports/", {"user_id": self.bob.id, "reason": "harassment", "message_id": message_id}, format="json"
        )
        self.assertEqual(response.status_code, 400)
