from django.shortcuts import render
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.response import Response
from rest_framework import status
from .models import Ride_Request
from Bikes.models import Bikes
from Trip.models import Trip
from Bikes.pricing import calculate_price
from math import radians, sin, cos, sqrt, atan2
from django.utils import timezone
from chat.models import ChatRoom, Message
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync

def calculate_distance(lat1, lon1, lat2, lon2):
    R = 6371  # Earth's radius in kilometers
    lat1, lon1, lat2, lon2 = map(radians, [float(lat1), float(lon1), float(lat2), float(lon2)])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    return R * c

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def request_ride(request):
    pickup_latitude = request.data.get('pickup_latitude')
    pickup_longitude = request.data.get('pickup_longitude')
    destination_latitude = request.data.get('destination_latitude')
    destination_longitude = request.data.get('destination_longitude')
    payment_type = request.data.get('payment_type')
    
    trip_distance = calculate_distance(
        pickup_latitude, pickup_longitude,
        destination_latitude, destination_longitude
    )
    
    available_bikes = Bikes.objects.filter(is_available=True)
    bikes_with_distance = []
    
    for bike in available_bikes:
        distance_to_rider = calculate_distance(
            pickup_latitude, pickup_longitude,
            bike.latitude, bike.longitude
        )
        bikes_with_distance.append((bike, distance_to_rider))
    
    if not bikes_with_distance:
        return Response({'error': 'No available bikes nearby'}, status=status.HTTP_404_NOT_FOUND)
    
    nearest_bike, distance_to_bike = min(bikes_with_distance, key=lambda x: x[1])
    
    estimated_price = calculate_price(
        distance=trip_distance,
        duration_hours=trip_distance/30
    )
    
    ride_request = Ride_Request.objects.create(
    Rider=request.user.userprofile,
    Owner=nearest_bike.owner,
    bike=nearest_bike,
    pickup_latitude=pickup_latitude,
    pickup_longitude=pickup_longitude,
    destination_latitude=destination_latitude,
    destination_longitude=destination_longitude,
    distance=trip_distance,
    price=estimated_price,
    payment_type=payment_type,
    duration=timedelta(hours=trip_distance/30)  
)
    
    # Send WebSocket notification to bike owner
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'notifications_{nearest_bike.owner.user.id}',
        {
            'type': 'send_notification',
            'title': 'New Ride Request',
            'message': f'New ride request worth ${estimated_price}',
            'data': {
                'request_id': ride_request.id,
                'pickup': f"{pickup_latitude}, {pickup_longitude}",
                'price': str(estimated_price)
            }
        }
    )
    
    return Response({
        'request_id': ride_request.id,
        'bike': {
            'id': nearest_bike.id,
            'name': nearest_bike.bike_name,
            'distance': distance_to_bike
        },
        'estimated_price': estimated_price,
        'estimated_duration': trip_distance/30
    }, status=status.HTTP_201_CREATED)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def accept_ride_request(request, request_id):
    try:
        ride_request = Ride_Request.objects.get(pk=request_id, status='pending')
        bike = ride_request.bike
        
        if bike.owner.user != request.user:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        
        trip = Trip.objects.create(
            renter=ride_request.rider,
            bike_owner=bike.owner,
            bike=bike,
            origin_latitude=ride_request.pickup_latitude,
            origin_longitude=ride_request.pickup_longitude,
            destination_latitude=ride_request.destination_latitude,
            destination_longitude=ride_request.destination_longitude,
            distance=ride_request.distance,
            price=ride_request.price,
            payment_type=ride_request.payment_type,
            status='created'
        )
        
        unlock_code = bike.hardware.generate_unlock_code()
        chat_room = ChatRoom.objects.create(trip=trip)
        Message.objects.create(
            chat_room=chat_room,
            sender=request.user,
            content=f"Your bike unlock code is: {unlock_code}\nValid for 5 minutes."
        )
        
        trip.process_unlock_status(False)
        ride_request.status = 'accepted'
        ride_request.save()

        # Send WebSocket notification to rider
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{ride_request.rider.user.id}',
            {
                'type': 'send_notification',
                'title': 'Ride Request Accepted',
                'message': 'Your ride request has been accepted!',
                'data': {
                    'trip_id': trip.id,
                    'chat_room_id': chat_room.id
                }
            }
        )
        
        return Response({
            'message': 'Ride request accepted',
            'trip_id': trip.id,
            'chat_room_id': chat_room.id
        })
        
    except Ride_Request.DoesNotExist:
        return Response({'error': 'Ride request not found'}, status=status.HTTP_404_NOT_FOUND)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def decline_ride_request(request, request_id):
    try:
        ride_request = Ride_Request.objects.get(pk=request_id, status='pending')
        
        if ride_request.bike.owner.user != request.user:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        
        ride_request.status = 'declined'
        ride_request.save()
        
        # Send WebSocket notification to rider
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{ride_request.rider.user.id}',
            {
                'type': 'send_notification',
                'title': 'Ride Request Declined',
                'message': 'Your ride request has been declined',
                'data': {
                    'request_id': ride_request.id
                }
            }
        )
        
        return Response({'message': 'Ride request declined'})
        
    except Ride_Request.DoesNotExist:
        return Response({'error': 'Ride request not found'}, status=status.HTTP_404_NOT_FOUND)
