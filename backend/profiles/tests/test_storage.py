"""Photos must work with object storage (no local file paths), as used with a bucket."""

from django.core.files.storage import InMemoryStorage, storages
from django.test import TestCase, override_settings

from core.tests.helpers import client_for, image_file, make_user
from profiles.models import Photo

BUCKET_LIKE = {
    "default": {"BACKEND": "django.core.files.storage.InMemoryStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}


@override_settings(STORAGES=BUCKET_LIKE)
class ObjectStoragePhotoTests(TestCase):
    def setUp(self):
        storages._storages = {}  # pick up the overridden STORAGES
        self.owner = make_user("owner@example.com", gender="woman", looking_for=["man"])
        self.viewer = make_user("viewer@example.com", gender="man", looking_for=["woman"])

    def tearDown(self):
        storages._storages = {}

    def test_upload_serve_and_delete_without_local_files(self):
        owner = client_for(self.owner)
        created = owner.post("/api/v1/photos/", {"image": image_file()}, format="multipart")
        self.assertEqual(created.status_code, 201, created.json())
        photo = Photo.objects.get(pk=created.json()["id"])
        storage = photo.image.storage
        self.assertIsInstance(storage, InMemoryStorage)
        self.assertTrue(storage.exists(photo.image.name))
        self.assertEqual((photo.width, photo.height), (400, 400))

        served = client_for(self.viewer).get(f"/api/v1/photos/{photo.id}/file/")
        self.assertEqual(served.status_code, 200)
        self.assertEqual(served["Content-Type"], "image/jpeg")
        self.assertTrue(b"".join(served.streaming_content).startswith(b"\xff\xd8"))

        self.assertEqual(owner.delete(f"/api/v1/photos/{photo.id}/").status_code, 204)
        self.assertFalse(storage.exists(photo.image.name))
