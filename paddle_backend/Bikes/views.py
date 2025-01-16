from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from django.shortcuts import get_object_or_404
from Owner.models import OwnerProfile  
from Owner.serializers import BikesSerializer
from .models import Bikes, BikeHardware
from geopy.distance import geodesic
from .pricing import calculate_price
from django.utils import timezone
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
from Riderequest.views import calculate_distance

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def activate_bike(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id, owner=request.user.owner_profile)
    scanned_serial = request.data.get('serial_number')
    
    if bike.activate_with_hardware(scanned_serial):
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{request.user.id}',
            {
                'type': 'send_notification',
                'title': 'Bike Activated',
                'message': f'Bike {bike.bike_name} has been activated successfully',
                'data': {
                    'bike_id': bike.id,
                    'hardware_status': bike.get_hardware_status()
                }
            }
        )
        return Response({
            'message': 'Bike activated successfully',
            'hardware_status': bike.get_hardware_status()
        })
    return Response({'error': 'Invalid or already assigned hardware'}, status=400)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_bike_unlock_code(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id)
    if not bike.is_active or not bike.is_available or bike.bike_status != 'available':
        return Response({'error': 'Bike is not available'}, status=400)
    
    if bike.verify_unlock_code(request.data.get('code')):
        channel_layer = get_channel_layer()
        for user_id in [request.user.id, bike.owner.user.id]:
            async_to_sync(channel_layer.group_send)(
                f'notifications_{user_id}',
                {
                    'type': 'send_notification',
                    'title': 'Bike Unlocked',
                    'message': f'Bike {bike.bike_name} has been unlocked',
                    'data': {
                        'bike_id': bike.id,
                        'hardware_status': bike.get_hardware_status()
                    }
                }
            )
        return Response({
            'message': 'Bike unlocked successfully',
            'hardware_status': bike.get_hardware_status()
        })
    return Response({'error': 'Invalid unlock code'}, status=400)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def lock_bike(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id)
    if bike.lock_bike():
        channel_layer = get_channel_layer()
        for user_id in [request.user.id, bike.owner.user.id]:
            async_to_sync(channel_layer.group_send)(
                f'notifications_{user_id}',
                {
                    'type': 'send_notification',
                    'title': 'Bike Locked',
                    'message': f'Bike {bike.bike_name} has been locked',
                    'data': {
                        'bike_id': bike.id,
                        'hardware_status': bike.get_hardware_status()
                    }
                }
            )
        return Response({
            'message': 'Bike locked successfully',
            'hardware_status': bike.get_hardware_status()
        })
    return Response({'error': 'Could not lock bike'}, status=400)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def toggle_bike_availability(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id, owner=request.user.owner_profile)
    
    if not bike.is_active:
        return Response({'error': 'Bike must be activated first'}, status=400)
        
    bike.is_available = not bike.is_available
    bike.bike_status = 'available' if bike.is_available else 'disabled'
    bike.save()
    
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'notifications_{request.user.id}',
        {
            'type': 'send_notification',
            'title': 'Bike Availability Updated',
            'message': f'Bike {bike.bike_name} is now {"available" if bike.is_available else "hidden"}',
            'data': {
                'bike_id': bike.id,
                'is_available': bike.is_available,
                'bike_status': bike.bike_status
            }
        }
    )
    
    return Response({
        'message': f'Bike is now {"available" if bike.is_available else "hidden"} on the map',
        'is_available': bike.is_available,
        'bike_status': bike.bike_status
    })


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_nearby_bikes(request):
    rider_latitude = request.GET.get('latitude')
    rider_longitude = request.GET.get('longitude')
    
    if not rider_latitude or not rider_longitude:
        return Response(
            {'error': 'Latitude and longitude are required'}, 
            status=status.HTTP_400_BAD_REQUEST
        )

    available_bikes = Bikes.objects.filter(
        is_available=True,
        is_active=True,
        bike_status='available'
    ).select_related('owner', 'hardware')
    
    bikes_with_distance = []
    for bike in available_bikes:
        distance = calculate_distance(
            rider_latitude, rider_longitude,
            bike.latitude, bike.longitude
        )
        bikes_with_distance.append({
            'id': bike.id,
            'bike_name': bike.bike_name,
            'brand': bike.brand,
            'model': bike.model,
            'location': {
                'latitude': bike.latitude,
                'longitude': bike.longitude
            },
            'distance': round(distance, 2),
            'battery_level': bike.hardware.battery_level
        })
    
    bikes_with_distance.sort(key=lambda x: x['distance'])
    
    return Response(bikes_with_distance)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def add_bike(request):
    # Ensure user is an owner
    owner_profile = request.user.owner_profile
    
    # Get data from request
    bike_data = {
        'owner': owner_profile.id,
        'bike_name': request.data.get('bike_name'),
        'brand': request.data.get('brand'),
        'model': request.data.get('model'),
        'color': request.data.get('color'),
        'size': request.data.get('size'),
        'year': request.data.get('year'),
        'description': request.data.get('description')
    }
    
    serializer = BikesSerializer(data=bike_data)
    if serializer.is_valid():
        bike = serializer.save()
        
        # Send notification through WebSocket
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{request.user.id}',
            {
                'type': 'send_notification',
                'title': 'Bike Added',
                'message': f'Bike {bike.bike_name} has been added successfully',
                'data': serializer.data
            }
        )
        
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def remove_bike(request, bike_id):
    try:
        bike = Bikes.objects.get(pk=bike_id, owner=request.user.owner_profile)
        bike_name = bike.bike_name
        
        # If bike has hardware, unassign it
        if bike.hardware:
            hardware = bike.hardware
            hardware.is_assigned = False
            hardware.save()
            
        bike.delete()
        
        # Send notification through WebSocket
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f'notifications_{request.user.id}',
            {
                'type': 'send_notification',
                'title': 'Bike Removed',
                'message': f'Bike {bike_name} has been removed successfully',
                'data': {'bike_id': bike_id}
            }
        )
        
        return Response({
            'message': f'Bike {bike_name} removed successfully',
            'bike_id': bike_id
        }, status=status.HTTP_200_OK)
        
    except Bikes.DoesNotExist:
        return Response({
            'error': 'Bike not found or you do not have permission to remove it'
        }, status=status.HTTP_404_NOT_FOUND)


