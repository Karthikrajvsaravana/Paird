from datetime import timedelta

from django.test import TestCase
from django.utils import timezone

from core.tests.helpers import client_for, make_user
from subscriptions.models import Subscription


class SubscriptionTests(TestCase):
    def setUp(self):
        self.user = make_user("sub@example.com")
        self.client = client_for(self.user)

    def test_free_by_default_and_purchases_disabled(self):
        data = self.client.get("/api/v1/subscription/").json()
        self.assertEqual(data["entitlements"]["plan"], "free")
        self.assertFalse(data["purchases_enabled"])
        self.assertEqual([p["id"] for p in data["plans"]], ["free", "premium"])

    def test_checkout_never_simulates_success(self):
        response = self.client.post("/api/v1/subscription/checkout/", {"plan": "premium"}, format="json")
        self.assertEqual(response.status_code, 503)
        self.assertFalse(Subscription.objects.exists())
        self.assertEqual(self.client.get("/api/v1/subscription/").json()["entitlements"]["plan"], "free")

    def test_active_and_expired_subscriptions(self):
        sub = Subscription.objects.create(user=self.user, expires_at=timezone.now() + timedelta(days=1))
        self.assertTrue(self.client.get("/api/v1/subscription/").json()["entitlements"]["is_premium"])
        sub.expires_at = timezone.now() - timedelta(seconds=1)
        sub.save()
        self.assertFalse(self.client.get("/api/v1/subscription/").json()["entitlements"]["is_premium"])
