from unittest import mock

from django.contrib.auth import get_user_model
from django.core import mail
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from core.tests.helpers import PASSWORD

User = get_user_model()


class WelcomeEmailTests(TestCase):
    def register(self, identifier):
        with self.captureOnCommitCallbacks(execute=True):
            return APIClient().post(
                "/api/v1/auth/register/",
                {"full_name": "Asha Raman", "identifier": identifier, "password": PASSWORD},
                format="json",
            )

    def test_email_sign_up_sends_welcome_email_without_password(self):
        response = self.register("Asha@Example.com")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(len(mail.outbox), 1)
        message = mail.outbox[0]
        self.assertEqual(message.to, ["asha@example.com"])
        self.assertIn("Welcome to Paird", message.subject)
        self.assertIn("Hi Asha", message.body)
        self.assertIn("account has been created", message.body)
        html = message.alternatives[0][0]
        self.assertNotIn(PASSWORD, message.body + html)

    def test_phone_sign_up_sends_no_email(self):
        self.assertEqual(self.register("+919876543210").status_code, 201)
        self.assertEqual(len(mail.outbox), 0)

    def test_failed_registration_sends_no_email(self):
        self.register("asha@example.com")
        mail.outbox.clear()
        duplicate = self.register("asha@example.com")
        self.assertEqual(duplicate.status_code, 400)
        self.assertEqual(len(mail.outbox), 0)

    def test_mail_server_failure_does_not_break_registration(self):
        with mock.patch(
            "django.core.mail.EmailMultiAlternatives.send", side_effect=OSError("SMTP down")
        ), self.assertLogs("accounts.services", level="ERROR"):
            response = self.register("asha@example.com")
        self.assertEqual(response.status_code, 201)
        self.assertTrue(User.objects.filter(identity__email="asha@example.com").exists())

    @override_settings(PAIRD={**__import__("django.conf", fromlist=["settings"]).settings.PAIRD, "WELCOME_EMAIL_ENABLED": False})
    def test_can_be_disabled(self):
        self.assertEqual(self.register("asha@example.com").status_code, 201)
        self.assertEqual(len(mail.outbox), 0)
