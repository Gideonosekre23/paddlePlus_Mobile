import logging
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.http import HttpResponse
from rest_framework.permissions import AllowAny
from django.views.decorators.csrf import csrf_exempt
from rest_framework import status
from django.shortcuts import get_object_or_404
from Owner.models import OwnerProfile  
from Owner.serializers import BikesSerializer
from .models import Bikes, BikeHardware
from geopy.distance import geodesic
from .pricing import calculate_price, calculate_distance

logger = logging.getLogger(__name__)
from django.utils import timezone
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def add_bike(request):
    if hasattr(request.user, 'owner_profile'):
        owner_profile = request.user.owner_profile
        data = request.data.copy()
        data['owner'] = owner_profile.id

        serializer = BikesSerializer(data=data, context={'request': request})

        if serializer.is_valid():
            bike = serializer.save()
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        else:
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    else:
        return Response({'error': 'Only owners can add bikes.'}, status=status.HTTP_403_FORBIDDEN)

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_driver_bikes(request):
    try:
        owner_profile = OwnerProfile.objects.get(user=request.user)
    except OwnerProfile.DoesNotExist:
        return Response({'error': 'Driver profile not found'}, status=status.HTTP_404_NOT_FOUND)
    
    bikes = Bikes.objects.filter(owner=owner_profile).select_related('hardware')
    serializer = BikesSerializer(bikes, many=True, context={'request': request})  # ← ADD THIS!
    return Response(serializer.data, status=status.HTTP_200_OK)



@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def activate_bike(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id, owner=request.user.owner_profile)
    scanned_serial = request.data.get('serial_number')
    
    if not scanned_serial:
        return Response({'error': 'Serial number is required'}, status=400)
    
    success, message = bike.activate_with_hardware(scanned_serial)
    if success:
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
            'message': message,
            'hardware_status': bike.get_hardware_status()
        })
    return Response({'error': message}, status=400)




@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_bike_unlock_code(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id)

    # Only the rider with an active trip on this bike may submit an unlock code
    from Trip.models import Trip
    has_active_trip = Trip.objects.filter(
        renter=request.user.userprofile,
        bike=bike,
        status__in=['started', 'ontrip']
    ).exists() if hasattr(request.user, 'userprofile') else False

    if not has_active_trip:
        return Response({'error': 'No active trip for this bike'}, status=status.HTTP_403_FORBIDDEN)

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

    # Only the owner of the bike or the rider with an active trip may lock it
    is_owner = hasattr(request.user, 'owner_profile') and bike.owner == request.user.owner_profile
    is_active_rider = False
    if hasattr(request.user, 'userprofile'):
        from Trip.models import Trip
        is_active_rider = Trip.objects.filter(
            renter=request.user.userprofile,
            bike=bike,
            status__in=['started', 'ontrip']
        ).exists()

    if not is_owner and not is_active_rider:
        return Response({'error': 'Not authorized to lock this bike'}, status=status.HTTP_403_FORBIDDEN)

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
        bike_status='available',
        latitude__isnull=False,
        longitude__isnull=False,
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
            'bike_address': bike.bike_address,
            'distance': round(distance, 2),
            'battery_level': bike.hardware.battery_level if bike.hardware else None,
            'bike_image': bike.bike_image.url if bike.bike_image else None
        })
    
    bikes_with_distance.sort(key=lambda x: x['distance'])
    
    return Response(bikes_with_distance)


@api_view(['POST'])
@csrf_exempt  # Arduino can't handle CSRF tokens
@permission_classes([AllowAny])  # No JWT auth for hardware
def receive_hardware_gps(request):

    try:
        # Get data from Arduino POST request
        HARDWARE_SERIAL = request.POST.get('HARDWARE_SERIAL')  # Hardware serial_number
        lat = request.POST.get('lat')
        lon = request.POST.get('lon')
        battery = request.POST.get('battery')
        
        # Validate required fields
        if not all([HARDWARE_SERIAL, lat, lon, battery]):
            return HttpResponse(" Missing required data", status=400)
        
        # Find hardware by serial_number
        try:
            hardware = BikeHardware.objects.get(serial_number=HARDWARE_SERIAL)
        except BikeHardware.DoesNotExist:
            return HttpResponse(" Hardware not found", status=404)
        
        # Convert to float and validate
        latitude = float(lat)
        longitude = float(lon)
        battery_level = int(battery) if battery else None
        
        # Update hardware location and status
        hardware.update_location(latitude, longitude)
        if battery_level is not None:
            hardware.update_status(battery_level=battery_level)

        logger.debug(f"GPS update: serial={HARDWARE_SERIAL} lat={lat} lon={lon} battery={battery}%")
        
        return HttpResponse(" GPS received", status=200)
        
    except ValueError as e:
        return HttpResponse(f"Invalid data format: {str(e)}", status=400)
    except Exception as e:
        return HttpResponse(f" Server error: {str(e)}", status=500)




@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_bike(request, bike_id):
    """Get details for a single bike."""
    bike = get_object_or_404(Bikes, pk=bike_id)
    serializer = BikesSerializer(bike, context={'request': request})
    return Response(serializer.data, status=status.HTTP_200_OK)


@api_view(['PUT', 'PATCH'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def edit_bike(request, bike_id):
    """Owner updates editable bike details."""
    bike = get_object_or_404(Bikes, pk=bike_id)

    if not hasattr(request.user, 'owner_profile') or bike.owner != request.user.owner_profile:
        return Response({'error': 'Not authorized to edit this bike'}, status=status.HTTP_403_FORBIDDEN)

    # Block hardware-managed and ownership fields from being changed here
    protected = {'owner', 'is_active', 'hardware', 'hardware_status', 'latitude', 'longitude',
                 'last_location_update', 'total_earnings', 'total_trips', 'total_distance'}
    data = {k: v for k, v in request.data.items() if k not in protected}

    serializer = BikesSerializer(bike, data=data, partial=True, context={'request': request})
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_200_OK)
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


