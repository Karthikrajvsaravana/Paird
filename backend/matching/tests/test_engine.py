from io import StringIO

from django.core.management import call_command
from django.test import TestCase

from accounts.models import AccountIdentity
from core.tests.helpers import client_for, make_user
from matching.compatibility import DEALBREAKER_CAP, vibe_for
from matching.demo_profiles import MEN, WOMEN, demo_email
from profiles.services import OTHER, get_preference


def user_for(person):
    return AccountIdentity.objects.get(email=demo_email(person["name"])).user


class DemoMatchQualityTests(TestCase):
    """The engine must rank each demo member's intended partner first."""

    @classmethod
    def setUpTestData(cls):
        call_command("paird_seed_demo", "--no-photos", stdout=StringIO())

    def ranking(self, viewer_person, others):
        viewer = user_for(viewer_person)
        scored = []
        for other in others:
            profile = user_for(other).profile
            scored.append((vibe_for(viewer, profile, OTHER)["score"] or 0, other["pair"], other["name"]))
        return sorted(scored, reverse=True)

    def test_each_woman_ranks_her_intended_match_first(self):
        for woman in WOMEN:
            ranking = self.ranking(woman, MEN)
            self.assertEqual(ranking[0][1], woman["pair"], f"{woman['name']}: {ranking[:3]}")
            self.assertGreaterEqual(ranking[0][0], 75, f"{woman['name']} best match score too low: {ranking[0]}")

    def test_each_man_ranks_his_intended_match_first(self):
        for man in MEN:
            ranking = self.ranking(man, WOMEN)
            self.assertEqual(ranking[0][1], man["pair"], f"{man['name']}: {ranking[:3]}")

    def test_children_conflict_is_capped(self):
        meera = user_for(next(w for w in WOMEN if w["name"] == "Meera Joshi"))
        karthik = user_for(next(m for m in MEN if m["name"] == "Karthik Raman")).profile
        vibe = vibe_for(meera, karthik, OTHER)
        self.assertLessEqual(vibe["score"], DEALBREAKER_CAP)
        self.assertEqual(vibe["dealbreakers"], ["Children"])

    def test_discover_shows_best_matches_first(self):
        ananya = user_for(WOMEN[0])
        results = client_for(ananya).get("/api/v1/discover/").json()["results"]
        self.assertEqual(results[0]["display_name"], "Karthik R.")
        scores = [r["vibe"]["score"] for r in results]
        self.assertEqual(scores, sorted(scores, reverse=True))
        recent = client_for(ananya).get("/api/v1/discover/?sort=recent").json()["results"]
        self.assertEqual(len(recent), len(results))

    def test_dashboard_recommends_intended_match(self):
        riya = user_for(next(w for w in WOMEN if w["name"] == "Riya Patel"))
        recs = client_for(riya).get("/api/v1/dashboard/").json()["recommendations"]
        self.assertEqual(recs[0]["display_name"], "Jay S.")

    def test_seed_is_idempotent_and_removable(self):
        out = StringIO()
        call_command("paird_seed_demo", "--no-photos", stdout=out)
        self.assertIn("Created 0 demo account(s), 20 already existed", out.getvalue())
        call_command("paird_seed_demo", "--remove", stdout=StringIO())
        self.assertFalse(AccountIdentity.objects.filter(email__endswith="@demo.paird.test").exists())


class EngineRuleTests(TestCase):
    def setUp(self):
        self.me = make_user("me@example.com", gender="woman", looking_for=["man"],
                            wants_children="yes", marriage_timeline="6_to_12_months", diet="vegetarian")
        self.him = make_user("him@example.com", gender="man", looking_for=["woman"],
                             wants_children="yes", marriage_timeline="6_to_12_months", diet="non_vegetarian")

    def test_hidden_lifestyle_is_not_used(self):
        visible = vibe_for(self.me, self.him.profile, OTHER)
        self.assertIn("lifestyle", [b["key"] for b in visible["breakdown"]])
        self.him.profile.lifestyle_visibility = "hidden"
        self.him.profile.save()
        hidden = vibe_for(self.me, self.him.profile, OTHER)
        self.assertNotIn("lifestyle", [b["key"] for b in hidden["breakdown"]])

    def test_their_preferences_are_applied_but_not_revealed(self):
        pref = get_preference(self.him)
        pref.diets = ["non_vegetarian"]
        pref.save()
        vibe = vibe_for(self.me, self.him.profile, OTHER)
        their = next(b for b in vibe["breakdown"] if b["key"] == "their_fit")
        self.assertFalse(their["met"])
        self.assertEqual(set(their), {"key", "label", "met"})
        self.assertNotIn("non_vegetarian", str(vibe))
