from datetime import date, timedelta

from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone

from core.tests.helpers import client_for, make_user
from matching.compatibility import vibe_score
from matching.models import Interest, Match
from messaging.models import Conversation
from profiles.services import OTHER, get_preference
from safety.models import Block
from subscriptions.models import Subscription
from verification.models import VerificationRequest


def ids(response):
    return [item["user_id"] for item in response.json()["results"]]


class DiscoveryTests(TestCase):
    def setUp(self):
        self.me = make_user("me@example.com", gender="woman", looking_for=["man"], dob=date(1995, 1, 1))
        self.client = client_for(self.me)

    def test_requires_completed_profile(self):
        incomplete = make_user("inc@example.com", complete=False)
        self.assertEqual(client_for(incomplete).get("/api/v1/discover/").status_code, 403)

    def test_eligibility_rules(self):
        good = make_user("good@example.com", gender="man", looking_for=["woman"])
        make_user("wrong-gender@example.com", gender="woman", looking_for=["woman"])
        make_user("not-into-me@example.com", gender="man", looking_for=["man"])
        make_user("incomplete@example.com", gender="man", looking_for=["woman"], complete=False)
        hidden = make_user("hidden@example.com", gender="man", looking_for=["woman"])
        hidden.profile.discoverable = False
        hidden.profile.save()
        paused = make_user("paused@example.com", gender="man", looking_for=["woman"])
        paused.profile.is_paused = True
        paused.profile.save()
        inactive = make_user("inactive@example.com", gender="man", looking_for=["woman"])
        inactive.is_active = False
        inactive.save()
        blocked = make_user("blocked@example.com", gender="man", looking_for=["woman"])
        Block.objects.create(blocker=blocked, blocked=self.me)

        self.assertEqual(ids(self.client.get("/api/v1/discover/")), [good.id])

    def test_age_preferences_both_directions(self):
        older = make_user("older@example.com", gender="man", looking_for=["woman"], dob=date(1970, 1, 1))
        picky = make_user("picky@example.com", gender="man", looking_for=["woman"], dob=date(1994, 1, 1))
        fine = make_user("fine@example.com", gender="man", looking_for=["woman"], dob=date(1993, 1, 1))
        pref = get_preference(self.me)
        pref.age_min, pref.age_max = 25, 40
        pref.save()
        picky_pref = get_preference(picky)
        picky_pref.age_max = 22  # I am older than this member wants
        picky_pref.save()
        result = ids(self.client.get("/api/v1/discover/"))
        self.assertIn(fine.id, result)
        self.assertNotIn(older.id, result)
        self.assertNotIn(picky.id, result)

    def test_explicit_filters(self):
        a = make_user("a@example.com", gender="man", looking_for=["woman"], religion="hindu", city="Pune")
        b = make_user("b@example.com", gender="man", looking_for=["woman"], religion="christian", country="Canada")
        self.assertEqual(ids(self.client.get("/api/v1/discover/?religion=hindu")), [a.id])
        self.assertEqual(ids(self.client.get("/api/v1/discover/?country=canada")), [b.id])
        self.assertEqual(ids(self.client.get("/api/v1/discover/?city=pun")), [a.id])
        VerificationRequest.objects.create(user=b, status="approved")
        self.assertEqual(ids(self.client.get("/api/v1/discover/?verified_only=true")), [b.id])

    def test_pagination(self):
        for i in range(5):
            make_user(f"m{i}@example.com", gender="man", looking_for=["woman"])
        page1 = self.client.get("/api/v1/discover/?page_size=2").json()
        page3 = self.client.get("/api/v1/discover/?page_size=2&page=3").json()
        self.assertEqual(page1["count"], 5)
        self.assertTrue(page1["has_next"])
        self.assertEqual(len(page3["results"]), 1)
        self.assertFalse(page3["has_next"])

    def test_empty_database_is_handled(self):
        response = self.client.get("/api/v1/discover/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["results"], [])


class VibeScoreTests(TestCase):
    def test_score_is_fraction_of_met_preferences(self):
        me = make_user("me@example.com", gender="woman", looking_for=["man"])
        cand = make_user("c@example.com", gender="man", looking_for=["woman"], religion="hindu", diet="vegan", dob=date(1993, 1, 1))
        pref = get_preference(me)
        self.assertIsNone(vibe_score(pref, cand.profile, OTHER)["score"])
        pref.religions = ["hindu"]
        pref.diets = ["vegetarian"]
        pref.age_min, pref.age_max = 25, 40
        pref.marriage_timelines = ["6_to_12_months", "1_to_2_years"]
        pref.save()
        result = vibe_score(pref, cand.profile, OTHER)
        self.assertEqual(result["score"], 75)
        self.assertEqual({b["key"]: b["met"] for b in result["breakdown"]}, {"age": True, "religion": True, "timeline": True, "diet": False})

    def test_hidden_attributes_are_not_scored(self):
        me = make_user("me@example.com", gender="woman", looking_for=["man"])
        cand = make_user("c@example.com", gender="man", looking_for=["woman"], diet="vegan", lifestyle_visibility="matches")
        pref = get_preference(me)
        pref.diets = ["vegan"]
        pref.save()
        self.assertEqual(vibe_score(pref, cand.profile, OTHER), {"score": None, "breakdown": []})


class InterestLifecycleTests(TestCase):
    def setUp(self):
        self.alice = make_user("alice@example.com", gender="woman", looking_for=["man"])
        self.bob = make_user("bob@example.com", gender="man", looking_for=["woman"])
        self.carol = make_user("carol@example.com", gender="woman", looking_for=["man"])
        self.a, self.b, self.c = client_for(self.alice), client_for(self.bob), client_for(self.carol)

    def send(self, client, user, **extra):
        return client.post("/api/v1/interests/", {"receiver_id": user.id, **extra}, format="json")

    def test_send_is_idempotent(self):
        first = self.send(self.a, self.bob)
        second = self.send(self.a, self.bob)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.json()["interest"]["id"], second.json()["interest"]["id"])
        self.assertEqual(Interest.objects.count(), 1)

    def test_cannot_send_to_self_or_unknown(self):
        self.assertEqual(self.send(self.a, self.alice).status_code, 400)
        self.assertEqual(self.a.post("/api/v1/interests/", {"receiver_id": 999999}, format="json").status_code, 404)

    def test_accept_creates_match_and_conversation(self):
        interest_id = self.send(self.a, self.bob).json()["interest"]["id"]
        received = self.b.get("/api/v1/interests/?direction=received").json()["results"]
        self.assertEqual([r["id"] for r in received], [interest_id])
        response = self.b.post(f"/api/v1/interests/{interest_id}/accept/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(Match.objects.count(), 1)
        self.assertEqual(Conversation.objects.count(), 1)
        self.assertEqual(response.json()["interest"]["status"], "accepted")
        self.assertEqual(self.a.get("/api/v1/matches/").json()["count"], 1)
        # Repeat accept is rejected safely
        self.assertEqual(self.b.post(f"/api/v1/interests/{interest_id}/accept/").status_code, 409)
        # Cannot send interest to an existing match
        self.assertEqual(self.send(self.a, self.bob).status_code, 409)

    def test_mutual_interest_auto_matches(self):
        self.send(self.a, self.bob)
        response = self.send(self.b, self.alice)
        self.assertIsNotNone(response.json()["match"])
        self.assertEqual(Match.objects.count(), 1)
        self.assertEqual(Interest.objects.count(), 1)

    def test_only_receiver_can_accept_or_decline_and_only_sender_can_withdraw(self):
        interest_id = self.send(self.a, self.bob).json()["interest"]["id"]
        self.assertEqual(self.a.post(f"/api/v1/interests/{interest_id}/accept/").status_code, 404)
        self.assertEqual(self.c.post(f"/api/v1/interests/{interest_id}/accept/").status_code, 404)
        self.assertEqual(self.c.post(f"/api/v1/interests/{interest_id}/decline/").status_code, 404)
        self.assertEqual(self.b.post(f"/api/v1/interests/{interest_id}/withdraw/").status_code, 404)
        self.assertEqual(self.a.post(f"/api/v1/interests/{interest_id}/withdraw/").status_code, 200)
        self.assertEqual(self.b.post(f"/api/v1/interests/{interest_id}/accept/").status_code, 409)

    def test_decline_and_cooldown(self):
        interest_id = self.send(self.a, self.bob).json()["interest"]["id"]
        self.assertEqual(self.b.post(f"/api/v1/interests/{interest_id}/decline/").status_code, 200)
        self.assertEqual(self.send(self.a, self.bob).status_code, 409)
        Interest.objects.filter(pk=interest_id).update(responded_at=timezone.now() - timedelta(days=31))
        self.assertEqual(self.send(self.a, self.bob).status_code, 201)

    def test_interest_expires_after_seven_days_on_server(self):
        response = self.send(self.a, self.bob)
        interest = Interest.objects.get(pk=response.json()["interest"]["id"])
        self.assertAlmostEqual(
            (interest.expires_at - interest.created_at).total_seconds(), timedelta(days=7).total_seconds(), delta=1
        )
        Interest.objects.filter(pk=interest.pk).update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.b.post(f"/api/v1/interests/{interest.pk}/accept/").status_code, 409)
        interest.refresh_from_db()
        self.assertEqual(interest.status, "expired")
        self.assertEqual(Match.objects.count(), 0)
        # After expiry a fresh interest can be sent.
        self.assertEqual(self.send(self.a, self.bob).status_code, 201)

    def test_expire_command(self):
        self.send(self.a, self.bob)
        Interest.objects.update(expires_at=timezone.now() - timedelta(minutes=1))
        call_command("expire_interests", stdout=open("/dev/null", "w"))
        self.assertEqual(Interest.objects.get().status, "expired")

    @override_settings(PAIRD={**__import__("django.conf", fromlist=["settings"]).settings.PAIRD, "FREE_DAILY_INTEREST_LIMIT": 1})
    def test_daily_limit_and_premium_entitlement(self):
        self.assertEqual(self.send(self.b, self.alice).status_code, 201)
        response = self.send(self.b, self.carol)
        self.assertEqual(response.status_code, 403)
        Subscription.objects.create(user=self.bob, expires_at=timezone.now() + timedelta(days=30))
        self.assertEqual(self.send(self.b, self.carol).status_code, 201)

    def test_verified_only_receivers(self):
        self.bob.profile.interests_from = "verified"
        self.bob.profile.save()
        self.assertEqual(self.send(self.a, self.bob).status_code, 403)
        VerificationRequest.objects.create(user=self.alice, status="approved")
        self.assertEqual(self.send(self.a, self.bob).status_code, 201)

    def test_paused_members_cannot_send_or_receive(self):
        self.alice.profile.is_paused = True
        self.alice.profile.save()
        self.assertEqual(self.send(self.a, self.bob).status_code, 403)
        self.assertEqual(self.send(self.b, self.alice).status_code, 404)

    def test_blocked_users_cannot_interact(self):
        Block.objects.create(blocker=self.bob, blocked=self.alice)
        self.assertEqual(self.send(self.a, self.bob).status_code, 404)

    def test_block_ends_match_and_pending_interests(self):
        interest_id = self.send(self.a, self.bob).json()["interest"]["id"]
        self.b.post(f"/api/v1/interests/{interest_id}/accept/")
        self.send(self.c, self.bob)
        self.b.post("/api/v1/blocks/", {"user_id": self.alice.id}, format="json")
        self.assertIsNotNone(Match.objects.get().ended_at)
        self.assertEqual(self.a.get("/api/v1/matches/").json()["count"], 0)
        self.b.post("/api/v1/blocks/", {"user_id": self.carol.id}, format="json")
        self.assertEqual(Interest.objects.get(sender=self.carol).status, "declined")

    def test_end_match(self):
        interest_id = self.send(self.a, self.bob).json()["interest"]["id"]
        match_id = self.b.post(f"/api/v1/interests/{interest_id}/accept/").json()["match"]["id"]
        self.assertEqual(self.c.post(f"/api/v1/matches/{match_id}/end/").status_code, 404)
        self.assertEqual(self.a.post(f"/api/v1/matches/{match_id}/end/").status_code, 204)
        self.assertEqual(self.b.get("/api/v1/matches/").json()["count"], 0)

    def test_connection_status_in_discovery(self):
        self.send(self.b, self.alice)
        result = self.a.get("/api/v1/discover/").json()["results"]
        bob_card = next(r for r in result if r["user_id"] == self.bob.id)
        self.assertEqual(bob_card["connection"]["status"], "interest_received")
        # Bob does not see Alice again after sending (pending interest excluded)
        self.assertNotIn(self.alice.id, ids(self.b.get("/api/v1/discover/")))
