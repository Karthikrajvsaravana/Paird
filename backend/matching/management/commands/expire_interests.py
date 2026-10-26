from django.core.management.base import BaseCommand

from matching.models import Interest


class Command(BaseCommand):
    help = "Mark pending interests past their expiry time as expired. Safe to run repeatedly (e.g. hourly)."

    def handle(self, *args, **options):
        count = Interest.objects.expire_due()
        self.stdout.write(self.style.SUCCESS(f"Expired {count} interest(s)."))
