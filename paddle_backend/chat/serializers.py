from rest_framework import serializers
from .models import Message, ChatRoom
from django.contrib.auth.models import User

class MessageSerializer(serializers.ModelSerializer):
    sender_username = serializers.CharField(source='sender.username', read_only=True)
    sender_id = serializers.IntegerField(source='sender.id', read_only=True)
    
    class Meta:
        model = Message
        fields = ['id', 'content', 'sender', 'sender_id', 'sender_username', 'timestamp', 'is_read']
        read_only_fields = ['id', 'sender', 'timestamp', 'is_read']

class ChatRoomSerializer(serializers.ModelSerializer):
    messages = MessageSerializer(many=True, read_only=True)
    trip_id = serializers.IntegerField(source='trip.id', read_only=True)
    
    class Meta:
        model = ChatRoom
        fields = ['id', 'trip_id', 'created_at', 'messages']
