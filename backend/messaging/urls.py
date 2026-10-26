from django.urls import path

from . import views

urlpatterns = [
    path("conversations/", views.ConversationListView.as_view(), name="conversations"),
    path("conversations/<int:conversation_id>/messages/", views.MessageListView.as_view(), name="messages"),
    path("conversations/<int:conversation_id>/read/", views.MarkReadView.as_view(), name="conversation-read"),
]
