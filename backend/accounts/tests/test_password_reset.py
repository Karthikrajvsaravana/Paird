import re
from datetime import timedelta
from unittest import mock

from django.core import mail
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import PasswordResetCode
from accounts.services import issue_tokens
from core.tests.helpers import PASSWORD, client_for, make_user

REQUEST = "/api/v1/auth/password-reset/"
CONFIRM = "/api/v1/auth/password-reset/confirm/"
EMAIL = "forgot@example.com"


def code_in(message):
    return re.search(r"\b(\d{6})\b", message.body).group(1)


class PasswordResetFlowTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = make_user(EMAIL, complete=False)

    def request_code(self, identifier=EMAIL):
        return self.client.post(REQUEST, {"identifier": identifier}, format="json")

    def confirm(self, code, new_password="Fresh-Garden-77"):
        with self.captureOnCommitCallbacks(execute=True):
            return self.client.post(
                CONFIRM, {"identifier": EMAIL, "code": code, "new_password": new_password}, format="json"
            )

    def age_latest_code(self, seconds):
        latest = PasswordResetCode.objects.filter(user=self.user).latest("created_at")
        PasswordResetCode.objects.filter(pk=latest.pk).update(created_at=latest.created_at - timedelta(seconds=seconds))

    def test_response_includes_resend_delay_and_email_has_styled_code(self):
        response = self.request_code()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["resend_after_seconds"], 60)
        self.assertEqual(len(mail.outbox), 1)
        html = mail.outbox[0].alternatives[0][0]
        self.assertIn(code_in(mail.outbox[0]), html)

    def test_resend_within_cooldown_sends_nothing_new(self):
        self.request_code()
        second = self.request_code()
        self.assertEqual(second.status_code, 200)
        self.assertEqual(len(mail.outbox), 1)

    def test_resend_after_cooldown_sends_new_code_and_old_one_stops_working(self):
        self.request_code()
        first_code = code_in(mail.outbox[0])
        self.age_latest_code(61)
        self.request_code()
        self.assertEqual(len(mail.outbox), 2)
        second_code = code_in(mail.outbox[1])
        if first_code != second_code:
            self.assertEqual(self.confirm(first_code).status_code, 400)
        self.assertEqual(self.confirm(second_code).status_code, 200)

    def test_successful_reset_changes_password_signs_out_and_sends_security_email(self):
        tokens = issue_tokens(self.user)
        self.request_code()
        response = self.confirm(code_in(mail.outbox[0]))
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("Fresh-Garden-77"))
        refresh = self.client.post("/api/v1/auth/refresh/", {"refresh": tokens["refresh"]}, format="json")
        self.assertEqual(refresh.status_code, 401)
        self.assertEqual(mail.outbox[-1].subject, "Your Paird password was changed")
        self.assertNotIn("Fresh-Garden-77", mail.outbox[-1].body)
        login = self.client.post("/api/v1/auth/login/", {"identifier": EMAIL, "password": "Fresh-Garden-77"}, format="json")
        self.assertEqual(login.status_code, 200)

    def test_expired_code_rejected(self):
        self.request_code()
        code = code_in(mail.outbox[0])
        PasswordResetCode.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.confirm(code).status_code, 400)

    def test_code_locks_after_five_wrong_attempts(self):
        self.request_code()
        code = code_in(mail.outbox[0])
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            self.assertEqual(self.confirm(wrong).status_code, 400)
        self.assertEqual(self.confirm(code).status_code, 400)

    def test_weak_new_password_rejected_and_code_still_usable(self):
        self.request_code()
        code = code_in(mail.outbox[0])
        weak = self.confirm(code, new_password="12345678")
        self.assertEqual(weak.status_code, 400)
        self.assertIn("new_password", weak.json()["error"]["fields"])
        self.assertEqual(self.confirm(code).status_code, 200)

    def test_mail_server_failure_returns_same_generic_response(self):
        with mock.patch("django.core.mail.EmailMultiAlternatives.send", side_effect=OSError("SMTP down")), self.assertLogs(
            "accounts.services", level="ERROR"
        ):
            response = self.request_code()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["detail"], self.request_code().json()["detail"])

    def test_unknown_and_deactivated_accounts_get_same_response_and_no_email(self):
        known = self.request_code().json()
        mail.outbox.clear()
        unknown = self.request_code("nobody@example.com").json()
        self.assertEqual(known, unknown)
        self.user.is_active = False
        self.user.save()
        PasswordResetCode.objects.all().delete()
        self.request_code()
        self.assertEqual(len(mail.outbox), 0)


class PasswordChangeNotificationTests(TestCase):
    def test_change_password_sends_security_email(self):
        user = make_user("changer@example.com")
        response = client_for(user).post(
            "/api/v1/auth/change-password/",
            {"current_password": PASSWORD, "new_password": "Quiet-River-58"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(mail.outbox[-1].subject, "Your Paird password was changed")
        self.assertEqual(mail.outbox[-1].to, ["changer@example.com"])
