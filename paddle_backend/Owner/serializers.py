import logging
from rest_framework import serializers
from Rider.models import UserProfile
from Riderequest.models import Ride_Request
from .models import OwnerProfile
from Bikes.models import Bikes
from chat.models import Message, ChatRoom
import base64
from django.core.files.base import ContentFile
import uuid

logger = logging.getLogger(__name__)


def _decode_base64_image(data_string, prefix):
    """Strip optional data: URL prefix and decode base64 to ContentFile."""
    if data_string.startswith('data:'):
        _, data_string = data_string.split(',', 1)
    return ContentFile(base64.b64decode(data_string), name=f'{prefix}_{uuid.uuid4()}.jpg')

class UserProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username')
    email = serializers.EmailField(source='user.email')
               
    class Meta:
        model = UserProfile
        fields = ['username', 'email', 'address', 'phone_number', 'profile_picture', 'verification_status', 'rider_rating', 'rider_rating_count']
    
    def to_internal_value(self, data):
        data = data.copy() if hasattr(data, 'copy') else dict(data)
        if 'profile_picture' in data and isinstance(data['profile_picture'], str):
            try:
                data['profile_picture'] = _decode_base64_image(data['profile_picture'], 'profile')
            except Exception as e:
                logger.warning(f"Profile picture base64 decode failed: {e}")
                data.pop('profile_picture', None)
        return super().to_internal_value(data)

    def update(self, instance, validated_data):
        
        user_data = validated_data.pop('user', {})
               
        
        if user_data:
            user = instance.user
            for attr, value in user_data.items():
                setattr(user, attr, value)
            user.save()
               
        # Update UserProfile fields (address, phone_number, profile_picture)
        return super().update(instance, validated_data)




class OwnerProfileSerializer(serializers.ModelSerializer):
    username = serializers.ReadOnlyField(source='user.username')
    email = serializers.ReadOnlyField(source='user.email')
    
    class Meta:
        model = OwnerProfile
        fields = ['username', 'email', 'address', 'phone_number', 'profile_picture', 'verification_status']

    def to_internal_value(self, data):
        data = data.copy() if hasattr(data, 'copy') else dict(data)
        if 'profile_picture' in data and isinstance(data['profile_picture'], str):
            try:
                data['profile_picture'] = _decode_base64_image(data['profile_picture'], 'profile')
            except Exception as e:
                logger.warning(f"Owner profile picture base64 decode failed: {e}")
                data.pop('profile_picture', None)
        return super().to_internal_value(data)

    def update(self, instance, validated_data):
        user_data = validated_data.pop('user', {})
        if user_data:
            user = instance.user
            for attr, value in user_data.items():
                setattr(user, attr, value)
            user.save()
        return super().update(instance, validated_data)











class BikesSerializer(serializers.ModelSerializer):
    current_location = serializers.SerializerMethodField()
    hardware_info = serializers.SerializerMethodField()
    total_earnings = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    total_trips = serializers.IntegerField(read_only=True)

    class Meta:
        model = Bikes
        fields = [
            'id',
            'owner',
            'bike_name',
            'brand',
            'model',
            'color',
            'size',
            'year',
            'description',
            'is_available',
            'is_active',
            'bike_status',
            'hardware_status',
            'latitude',
            'longitude',
            'bike_address',
            'bike_image',
            'rating',
            'rating_count',
            'total_earnings',
            'total_trips',
            'current_location',
            'hardware_info',
        ]
    
    def get_current_location(self, obj):
        if obj.latitude is not None and obj.longitude is not None:
            return {'latitude': obj.latitude, 'longitude': obj.longitude}
        return None
    

      
    def to_internal_value(self, data):
        data = data.copy() if hasattr(data, 'copy') else dict(data)
        if 'bike_image' in data and isinstance(data['bike_image'], str):
            try:
                data['bike_image'] = _decode_base64_image(data['bike_image'], 'bike')
            except Exception as e:
                logger.warning(f"Bike image base64 decode failed: {e}")
                data.pop('bike_image', None)
        return super().to_internal_value(data)







    def get_hardware_info(self, obj):
        """Return hardware information if hardware is assigned"""
        if hasattr(obj, 'hardware') and obj.hardware:
            return {
                'serial_number': obj.hardware.serial_number,
                'is_assigned': obj.hardware.is_assigned,
                'is_online': obj.hardware.is_online,
                'battery_level': obj.hardware.battery_level,
                'signal_strength': obj.hardware.signal_strength,
                'firmware_version': obj.hardware.firmware_version,
                'last_ping': obj.hardware.last_ping.isoformat() if obj.hardware.last_ping else None,
            }
        return None
    

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if instance.bike_image and hasattr(instance.bike_image, 'url'):
            request = self.context.get('request')
            if request:
                data['bike_image'] = request.build_absolute_uri(instance.bike_image.url)
        return data




    def create(self, validated_data):
        user = self.context['request'].user
        driver_profile = OwnerProfile.objects.get(user=user)
        validated_data['owner'] = driver_profile
        validated_data['is_available'] = False
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



