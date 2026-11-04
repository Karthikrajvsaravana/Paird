"""
Copy photos and selfies that were saved on this computer (MEDIA_ROOT) into
the configured bucket, keeping the same names so database records stay valid.

    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_move_media --dry-run
    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_move_media
    .\\backend\\.venv\\Scripts\\python.exe .\\backend\\manage.py paird_move_media --delete-local

Local files are only deleted with --delete-local, and only after the copy in
the bucket has been verified.
"""

from pathlib import Path

from django.conf import settings
from django.core.files.storage import FileSystemStorage, default_storage
from django.core.management.base import BaseCommand, CommandError

from profiles.models import Photo
from verification.models import VerificationRequest


class Command(BaseCommand):
    help = "Move uploaded files from this computer's MEDIA_ROOT into the S3 bucket."

    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true", help="Only list what would be copied.")
        parser.add_argument("--delete-local", action="store_true", help="Delete local files after a verified copy.")

    def handle(self, *args, **options):
        if settings.STORAGE_BACKEND != "s3":
            raise CommandError("Set STORAGE_BACKEND=s3 (and the STORAGE_S3_* values) in backend/.env first.")
        local = FileSystemStorage(location=settings.MEDIA_ROOT)
        names = [p.image.name for p in Photo.objects.exclude(image="")]
        names += [v.selfie.name for v in VerificationRequest.objects.exclude(selfie="").exclude(selfie__isnull=True)]

        copied = skipped = missing = deleted = 0
        for name in names:
            source = Path(settings.MEDIA_ROOT) / name
            if not source.exists():
                if default_storage.exists(name):
                    skipped += 1
                else:
                    missing += 1
                    self.stdout.write(self.style.WARNING(f"Missing everywhere: {name}"))
                continue
            if default_storage.exists(name):
                skipped += 1
            elif options["dry_run"]:
                self.stdout.write(f"Would copy: {name}")
                copied += 1
                continue
            else:
                with local.open(name, "rb") as handle:
                    saved = default_storage.save(name, handle)
                if saved != name:
                    raise CommandError(f"Bucket stored {name} as {saved}; stopping so records stay consistent.")
                copied += 1
            if options["delete_local"] and not options["dry_run"]:
                if default_storage.exists(name) and default_storage.size(name) == source.stat().st_size:
                    source.unlink()
                    deleted += 1
                else:
                    self.stdout.write(self.style.WARNING(f"Kept local file (bucket copy not verified): {name}"))

        verb = "Would copy" if options["dry_run"] else "Copied"
        self.stdout.write(self.style.SUCCESS(
            f"{verb} {copied}, already in bucket {skipped}, missing {missing}, local files deleted {deleted}."
        ))
