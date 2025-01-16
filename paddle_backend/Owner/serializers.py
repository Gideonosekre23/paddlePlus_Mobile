
from rest_framework import serializers
from Rider.models import UserProfile  
from Riderequest.models import Ride_Request
from .models import OwnerProfile  
from Bikes.models import Bikes
from chat.models import Message, ChatRoom
# from django.contrib.gis.geos import Point

class UserProfileSerializer(serializers.ModelSerializer) :
    username = serializers.ReadOnlyField(source='user.username')
    email = serializers.ReadOnlyField(source='user.email')
    class Meta:
        model= UserProfile
        fields =  ['username', 'email', 'address', 'phone_number' ,'profile_picture']

class RideRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = Ride_Request
        fields = ['id', 'customer', 'pickup_location', 'destination','Price', 'requested_time', 'is_accepted', 'driver']
# 


class OwnerProfileSerializer(serializers.ModelSerializer):
    username = serializers.ReadOnlyField(source='user.username')
    email = serializers.ReadOnlyField(source='user.email')
    class Meta:
        model = OwnerProfile
        # fields = ['user', 'profile_picture', 'cpn', 'phone_number', 'created_on', 'edited_at', 'latitude', 'longitude']
        fields =  ['username', 'email', 'phone_number' ,'profile_picture']

class BikesSerializer(serializers.ModelSerializer):
    # current_location = serializers.SerializerMethodField()

    class Meta:
        model = Bikes
        fields = ['owner', 'bike_name', 'brand', 'model', 'color', 'size', 'year', 'description', 'is_available', 'latitude', 'longitude']

    def get_current_location(self, obj):
        if obj.latitude is not None and obj.longitude is not None:
            return {'latitude': obj.latitude, 'longitude': obj.longitude}
        return None

    def create(self, validated_data):
        user = self.context['request'].user
        driver_profile = OwnerProfile.objects.get(user=user)
        validated_data['owner'] = driver_profile
        validated_data['is_available'] = False
        # validated_data['latitude'] = driver_profile.latitude
        # validated_data['longitude'] = driver_profile.longitude
        bike = Bikes.objects.create(**validated_data)
        return bike
    

    # Add these to your existing serializers

class MessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.CharField(source='sender.username', read_only=True)
    
    class Meta:
        model = Message
        fields = ['id', 'sender_name', 'content', 'timestamp', 'is_read']

class ChatRoomSerializer(serializers.ModelSerializer):
    messages = MessageSerializer(many=True, read_only=True)
    
    class Meta:
        model = ChatRoom
        fields = ['id', 'trip', 'messages', 'created_at']
