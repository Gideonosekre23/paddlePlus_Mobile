
from rest_framework import serializers
from Rider.models import UserProfile  
from Riderequest.models import Ride_Request
from .models import OwnerProfile  
from Bikes.models import Bikes
from chat.models import Message, ChatRoom
# from django.contrib.gis.geos import Point

class UserProfileSerializer(serializers.ModelSerializer):
    username = serializers.ReadOnlyField(source='user.username')
    email = serializers.ReadOnlyField(source='user.email')

    class Meta:
        model = UserProfile
        fields = ['username', 'email', 'address', 'phone_number', 'profile_picture']
        extra_kwargs = {'profile_picture': {'required': False}}

class RideRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = Ride_Request
        fields = ['id', 'Rider', 'Owner', 'bike', 'pickup_latitude', 'pickup_longitude',
                  'destination_latitude', 'destination_longitude', 'price', 'requested_time',
                  'is_accepted', 'status', 'payment_type']
# 


class OwnerProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = OwnerProfile
        fields = ['user', 'profile_picture', 'cpn', 'phone_number', 'address', 'created_on', 'edited_at', 'latitude', 'longitude']
        extra_kwargs = {
            'user': {'read_only': True},
            'profile_picture': {'required': False},
        }

class BikesSerializer(serializers.ModelSerializer):
    # current_location = serializers.SerializerMethodField()

    class Meta:
        model = Bikes
        fields = ['owner', 'brand', 'model', 'color', 'size', 'year', 'description', 'is_available', 'latitude', 'longitude']

    def get_current_location(self, obj):
        if obj.latitude is not None and obj.longitude is not None:
            return {'latitude': obj.latitude, 'longitude': obj.longitude}
        return None

    def create(self, validated_data):
        user = self.context['request'].user
        owner_profile = OwnerProfile.objects.get(user=user)
        validated_data['owner'] = owner_profile
        validated_data['is_available'] = False
        bike = Bikes.objects.create(**validated_data)
        return bike
    

    # Add these to your existing serializers

class MessageSerializer(serializers.ModelSerializer):
    sender_username = serializers.CharField(source='sender.username', read_only=True)
    sender_id = serializers.IntegerField(source='sender.id', read_only=True)
    sender = serializers.IntegerField(source='sender.id', read_only=True)

    class Meta:
        model = Message
        fields = ['id', 'sender', 'sender_id', 'sender_username', 'content', 'timestamp', 'is_read']

class ChatRoomSerializer(serializers.ModelSerializer):
    messages = MessageSerializer(many=True, read_only=True)
    
    class Meta:
        model = ChatRoom
        fields = ['id', 'trip', 'messages', 'created_at']
