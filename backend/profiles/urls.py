from django.urls import path

from . import views

urlpatterns = [
    path("options/", views.OptionsView.as_view(), name="options"),
    path("profile/me/", views.MyProfileView.as_view(), name="my-profile"),
    path("profile/me/publish/", views.PublishProfileView.as_view(), name="publish-profile"),
    path("preferences/", views.PartnerPreferenceView.as_view(), name="preferences"),
    path("photos/", views.PhotoListView.as_view(), name="photos"),
    path("photos/<int:photo_id>/", views.PhotoDetailView.as_view(), name="photo-detail"),
    path("photos/<int:photo_id>/file/", views.PhotoFileView.as_view(), name="photo-file"),
    path("members/<int:user_id>/", views.MemberProfileView.as_view(), name="member-profile"),
]
