from django.db import models
from django.contrib.auth.models import User
from Trip.models import Trip

class ChatRoom(models.Model):
    trip = models.OneToOneField(Trip, on_delete=models.CASCADE, related_name='chat_room')
    created_at = models.DateTimeField(auto_now_add=True)
    
    def __str__(self):
        return f"Chat for Trip #{self.trip.id}"
    
    def get_other_user(self, current_user):
        """Get the other participant in this chat (not the current user)"""
        if self.trip.renter and self.trip.renter.user.id == current_user.id:
            return self.trip.bike_owner.user
        elif self.trip.bike_owner and self.trip.bike_owner.user.id == current_user.id:
            return self.trip.renter.user
        return None

class Message(models.Model):
    chat_room = models.ForeignKey(ChatRoom, on_delete=models.CASCADE, related_name='messages')
    sender = models.ForeignKey(User, on_delete=models.CASCADE)
    content = models.TextField()
    timestamp = models.DateTimeField(auto_now_add=True)
    is_read = models.BooleanField(default=False)

    class Meta:
        ordering = ['timestamp']

    def __str__(self):
        return f"Message from {self.sender.username} at {self.timestamp}"
