from django.urls import path

from . import views

urlpatterns = [
    path("discover/", views.DiscoverView.as_view(), name="discover"),
    path("interests/", views.InterestListView.as_view(), name="interests"),
    path("interests/<int:interest_id>/<str:action>/", views.InterestActionView.as_view(), name="interest-action"),
    path("matches/", views.MatchListView.as_view(), name="matches"),
    path("matches/<int:match_id>/end/", views.EndMatchView.as_view(), name="end-match"),
]
