"""Database-level guarantees (enforced by PostgreSQL, not just by the API)."""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase, override_settings
from django.utils import timezone

from accounts.models import AccountIdentity
from core.tests.helpers import PASSWORD, make_user
from matching.models import Interest, Match
from safety.models import Block

User = get_user_model()


class PasswordStorageTests(TestCase):
    @override_settings(PASSWORD_HASHERS=["django.contrib.auth.hashers.PBKDF2PasswordHasher"])
    def test_production_hasher_stores_pbkdf2_hash_never_plaintext(self):
        from rest_framework.test import APIClient

        APIClient().post(
            "/api/v1/auth/register/",
            {"full_name": "Hash Check", "identifier": "hash@example.com", "password": PASSWORD},
            format="json",
        )
        stored = User.objects.get(identity__email="hash@example.com").password
        self.assertTrue(stored.startswith("pbkdf2_sha256$"))
        self.assertNotIn(PASSWORD, stored)


class ConstraintTests(TestCase):
    def setUp(self):
        self.a = make_user("a@example.com")
        self.b = make_user("b@example.com", gender="man", looking_for=["woman"])

    def test_identity_email_and_phone_are_unique(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            AccountIdentity.objects.create(user=User.objects.create(username="dup"), full_name="X", email="a@example.com")
        AccountIdentity.objects.filter(user=self.a).update(phone="+919876543210")
        with self.assertRaises(IntegrityError), transaction.atomic():
            AccountIdentity.objects.create(user=User.objects.create(username="dup2"), full_name="X", phone="+919876543210")

    def test_identity_requires_email_or_phone(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            AccountIdentity.objects.create(user=User.objects.create(username="none"), full_name="X")

    def test_only_one_pending_interest_per_pair(self):
        expires = timezone.now() + timedelta(days=7)
        Interest.objects.create(sender=self.a, receiver=self.b, expires_at=expires)
        with self.assertRaises(IntegrityError), transaction.atomic():
            Interest.objects.create(sender=self.a, receiver=self.b, expires_at=expires)
        # A historical (non-pending) interest does not block a new one.
        Interest.objects.update(status="withdrawn")
        Interest.objects.create(sender=self.a, receiver=self.b, expires_at=expires)

    def test_no_self_interest_or_self_block(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            Interest.objects.create(sender=self.a, receiver=self.a, expires_at=timezone.now())
        with self.assertRaises(IntegrityError), transaction.atomic():
            Block.objects.create(blocker=self.a, blocked=self.a)

    def test_match_pair_is_unique_and_ordered(self):
        low, high = sorted([self.a.id, self.b.id])
        Match.objects.create(user_a_id=low, user_b_id=high)
        with self.assertRaises(IntegrityError), transaction.atomic():
            Match.objects.create(user_a_id=low, user_b_id=high)
        with self.assertRaises(IntegrityError), transaction.atomic():
            Match.objects.create(user_a_id=high, user_b_id=low)


class ServerSideEntitlementTests(TestCase):
    def test_client_cannot_grant_premium_or_verification(self):
        from core.tests.helpers import client_for

        user = make_user("c@example.com")
        client = client_for(user)
        client.patch("/api/v1/profile/me/", {"is_premium": True, "plan": "premium", "is_verified": True}, format="json")
        client.patch("/api/v1/settings/", {"privacy": {"is_premium": True}}, format="json")
        client.post("/api/v1/subscription/checkout/", {"plan": "premium"}, format="json")
        me = client.get("/api/v1/auth/me/").json()
        self.assertEqual(me["subscription"]["plan"], "free")
        self.assertEqual(me["verification_status"], "unverified")
