from django.test import TestCase

from core.locations import canonical_state, find_country
from core.tests.helpers import client_for, make_user


class LocationDataTests(TestCase):
    def test_lookup_by_name_or_code(self):
        self.assertEqual(find_country("india")["name"], "India")
        self.assertEqual(find_country("IN")["name"], "India")
        self.assertIsNone(find_country("Atlantis"))
        self.assertEqual(canonical_state(find_country("India"), "tamil  nadu"), "Tamil Nadu")
        self.assertEqual(find_country("United Kingdom")["states"], ["England", "Northern Ireland", "Scotland", "Wales"])


class LocationApiTests(TestCase):
    def setUp(self):
        self.user = make_user("loc@example.com", complete=False)
        self.client = client_for(self.user)

    def test_country_and_state_lists(self):
        countries = self.client.get("/api/v1/locations/countries/").json()
        self.assertGreater(len(countries), 200)
        india = next(c for c in countries if c["code"] == "IN")
        self.assertTrue(india["has_states"])
        states = self.client.get("/api/v1/locations/countries/IN/states/").json()
        self.assertIn("Kerala", states["states"])
        self.assertEqual(self.client.get("/api/v1/locations/countries/XX/states/").status_code, 404)

    def test_requires_sign_in(self):
        from rest_framework.test import APIClient

        self.assertEqual(APIClient().get("/api/v1/locations/countries/").status_code, 401)

    def test_profile_country_and_state_are_validated_and_normalised(self):
        ok = self.client.patch("/api/v1/profile/me/", {"country": "india", "state": "tamil nadu"}, format="json")
        self.assertEqual(ok.status_code, 200, ok.json())
        self.assertEqual((ok.json()["country"], ok.json()["state"]), ("India", "Tamil Nadu"))
        bad_country = self.client.patch("/api/v1/profile/me/", {"country": "Atlantis"}, format="json")
        self.assertEqual(bad_country.status_code, 400)
        bad_state = self.client.patch("/api/v1/profile/me/", {"state": "Ontario"}, format="json")
        self.assertEqual(bad_state.status_code, 400)

    def test_changing_country_clears_old_state(self):
        self.client.patch("/api/v1/profile/me/", {"country": "India", "state": "Kerala"}, format="json")
        response = self.client.patch("/api/v1/profile/me/", {"country": "Canada"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["state"], "")

    def test_preference_countries_validated(self):
        ok = self.client.patch("/api/v1/preferences/", {"countries": ["india", "CA"]}, format="json")
        self.assertEqual(ok.json()["countries"], ["India", "Canada"])
        bad = self.client.patch("/api/v1/preferences/", {"countries": ["Atlantis"]}, format="json")
        self.assertEqual(bad.status_code, 400)
