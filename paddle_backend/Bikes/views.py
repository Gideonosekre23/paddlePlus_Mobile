from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.permissions import IsAuthenticated, AllowAny
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
from paddle_backend.geo_utils import calculate_distance
from chat.utils import notify_user
import base64
import logging
from django.core.files.base import ContentFile
logger = logging.getLogger(__name__)

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def activate_bike(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id, owner=request.user.owner_profile)
    scanned_data = {
        'serial': request.data.get('serial_number', ''),
        'key': request.data.get('factory_key', ''),
    }
    if bike.activate_with_hardware(scanned_data):
        notify_user(request.user.id, 'Bike Activated', f'Bike {bike.bike_name} has been activated successfully', {
            'bike_id': bike.id,
            'hardware_status': bike.get_hardware_status(),
        })
        return Response({
            'message': 'Bike activated successfully',
            'hardware_status': bike.get_hardware_status(),
        })
    return Response({'error': 'Invalid or already assigned hardware'}, status=400)

@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_bike_unlock_code(request, bike_id):
    from Trip.models import Trip
    bike = get_object_or_404(Bikes, pk=bike_id)

    # Only the renter of an active trip on this bike can request the code
    active_trip = Trip.objects.filter(
        bike=bike,
        renter=request.user.userprofile,
        status__in=['waiting', 'started']
    ).first()

    if not active_trip:
        return Response({'error': 'No active trip found for this bike'}, status=403)

    if not bike.hardware:
        return Response({'error': 'Bike has no hardware attached'}, status=400)

    unlock_code = bike.hardware.generate_unlock_code()

    return Response({
        'unlock_code': unlock_code,
        'bike_id': bike.id,
        'bike_name': bike.bike_name,
        'valid_seconds': 300,
    })

@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def lock_bike(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id)

    is_owner = hasattr(request.user, 'owner_profile') and bike.owner == request.user.owner_profile
    is_renter = False
    if hasattr(request.user, 'userprofile'):
        from Trip.models import Trip
        is_renter = Trip.objects.filter(
            bike=bike, renter=request.user.userprofile, status='ontrip'
        ).exists()

    if not (is_owner or is_renter):
        return Response({'error': 'Not authorized to lock this bike'}, status=403)

    if bike.lock_bike():
        for user_id in [request.user.id, bike.owner.user.id]:
            notify_user(user_id, 'Bike Locked', f'Bike {bike.bike_name} has been locked', {
                'bike_id': bike.id,
                'hardware_status': bike.get_hardware_status(),
            })
        return Response({
            'message': 'Bike locked successfully',
            'hardware_status': bike.get_hardware_status(),
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

    notify_user(request.user.id, 'Bike Availability Updated', f'Bike {bike.bike_name} is now {"available" if bike.is_available else "hidden"}', {
        'bike_id': bike.id,
        'is_available': bike.is_available,
        'bike_status': bike.bike_status,
    })
    
    return Response({
        'message': f'Bike is now {"available" if bike.is_available else "hidden"} on the map',
        'bike_id': bike.id,
        'is_available': bike.is_available,
        'bike_status': bike.bike_status
    })


def _bike_to_dict(bike, request=None):
    hw = bike.hardware
    if bike.bike_image:
        raw_url = bike.bike_image.url
        bike_image_url = request.build_absolute_uri(raw_url) if request else raw_url
    else:
        bike_image_url = None
    return {
        'id': bike.id,
        'bike_name': bike.bike_name,
        'brand': bike.brand,
        'model': bike.model,
        'color': bike.color,
        'size': bike.size,
        'year': bike.year,
        'description': bike.description,
        'latitude': bike.latitude,
        'longitude': bike.longitude,
        'bike_address': bike.bike_address,
        'is_available': bike.is_available,
        'is_active': bike.is_active,
        'bike_status': bike.bike_status,
        'hardware_status': bike.hardware_status,
        'battery_level': hw.battery_level if hw else None,
        'bike_image': bike_image_url,
        'owner_username': bike.owner.user.username,
        'hardware_info': {
            'is_assigned': hw.is_assigned,
            'battery_level': hw.battery_level,
            'serial_number': hw.serial_number,
            'status': bike.hardware_status,
            'is_online': hw.last_ping is not None,
            'signal_strength': None,
            'firmware_version': None,
            'assigned_at': hw.last_ping.isoformat() if hw.last_ping else None,
            'last_ping': hw.last_ping.isoformat() if hw.last_ping else None,
        } if hw else None,
        'created_at': bike.created_at.isoformat(),
        'updated_at': bike.updated_at.isoformat(),
    }


@api_view(['POST'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def add_bike(request):
    owner = get_object_or_404(OwnerProfile, user=request.user)
    bike = Bikes.objects.create(
        owner=owner,
        bike_name=request.data.get('bike_name', ''),
        brand=request.data.get('brand', ''),
        model=request.data.get('model', ''),
        color=request.data.get('color', ''),
        size=request.data.get('size', ''),
        year=request.data.get('year'),
        description=request.data.get('description', ''),
        latitude=request.data.get('latitude'),
        longitude=request.data.get('longitude'),
        bike_address=request.data.get('bike_address', ''),
        is_available=False,
        is_active=False,
        bike_status='disabled',
    )
    bike_image_data = request.data.get('bike_image')
    if bike_image_data and isinstance(bike_image_data, str):
        try:
            if ',' in bike_image_data:
                bike_image_data = bike_image_data.split(',', 1)[1]
            img_bytes = base64.b64decode(bike_image_data)
            bike.bike_image.save(
                f'bike_{bike.pk}.jpg',
                ContentFile(img_bytes),
                save=True,
            )
        except Exception as e:
            logger.warning(f'Bike image decode failed for bike {bike.pk}: {e}')
    elif 'bike_image' in request.FILES:
        bike.bike_image = request.FILES['bike_image']
        bike.save(update_fields=['bike_image'])
    return Response(_bike_to_dict(bike, request), status=status.HTTP_201_CREATED)


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_owner_bikes(request):
    owner = get_object_or_404(OwnerProfile, user=request.user)
    bikes = Bikes.objects.filter(owner=owner).select_related('hardware', 'owner__user')
    return Response([_bike_to_dict(b, request) for b in bikes])


@api_view(['DELETE'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def remove_bike(request, bike_id):
    bike = get_object_or_404(Bikes, pk=bike_id, owner=request.user.owner_profile)
    if bike.hardware:
        bike.hardware.is_assigned = False
        bike.hardware.save(update_fields=['is_assigned'])
    saved_id = bike.id
    bike.delete()
    return Response({'message': 'Bike removed successfully', 'bike_id': saved_id})


@api_view(['GET'])
@authentication_classes([JWTAuthentication])
@permission_classes([IsAuthenticated])
def get_nearby_bikes(request):
    
    try:
        rider_latitude = float(request.GET.get('latitude', ''))
        rider_longitude = float(request.GET.get('longitude', ''))
    except (ValueError, TypeError):
        return Response(
            {'error': 'Latitude and longitude must be valid numbers'},
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
            'bike_address': getattr(bike, 'bike_address', None),
            'distance': round(distance, 2),
            'battery_level': bike.hardware.battery_level if bike.hardware else None,
            'bike_image': request.build_absolute_uri(bike.bike_image.url) if bike.bike_image else None,
        })

    # Sort bikes by distance from rider
    bikes_with_distance.sort(key=lambda x: x['distance'])

    return Response(bikes_with_distance)


@api_view(['POST'])
@authentication_classes([])
@permission_classes([AllowAny])
def hardware_gps_update(request):
    """
    Endpoint for Arduino hardware to push GPS + battery data.
    Expected POST body (form-encoded):
        HARDWARE_SERIAL=<serial>&lat=<lat>&lon=<lon>&battery=<level>&api_key=<key>
    Set HARDWARE_API_KEY env var to require hardware authentication.
    """
    import os as _os
    _hw_key = _os.getenv('HARDWARE_API_KEY', '')
    provided = (
        request.data.get('api_key', '')
        or request.META.get('HTTP_X_HARDWARE_KEY', '')
    )
    if not _hw_key:
        # HARDWARE_API_KEY must be set in production; block all requests until it is
        return Response({'error': 'Hardware authentication not configured'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
    if provided != _hw_key:
        return Response({'error': 'Unauthorized'}, status=status.HTTP_401_UNAUTHORIZED)

    serial = request.data.get('HARDWARE_SERIAL')
    lat = request.data.get('lat')
    lon = request.data.get('lon')
    battery = request.data.get('battery')

    if not serial:
        return Response({'error': 'Missing HARDWARE_SERIAL'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        hardware = BikeHardware.objects.select_related('assigned_bike').get(serial_number=serial)
    except BikeHardware.DoesNotExist:
        return Response({'error': 'Hardware not found'}, status=status.HTTP_404_NOT_FOUND)

    now = timezone.now()
    hardware.last_ping = now

    if lat is not None and lon is not None:
        try:
            hardware.latitude = float(lat)
            hardware.longitude = float(lon)
            hardware.last_location_update = now
        except (TypeError, ValueError):
            return Response({'error': 'Invalid lat/lon'}, status=status.HTTP_400_BAD_REQUEST)

    if battery is not None:
        try:
            hardware.battery_level = int(float(battery))
        except (TypeError, ValueError):
            pass

    hardware.save()

    # Keep the Bikes record lat/lon in sync so get_nearby_bikes stays current
    bike = getattr(hardware, 'assigned_bike', None)
    if bike and lat is not None and lon is not None:
        bike.latitude = hardware.latitude
        bike.longitude = hardware.longitude
        bike.save(update_fields=['latitude', 'longitude'])

        # Push live bike location to the rider of any active trip on this bike
        from Trip.models import Trip as _Trip
        active_trip = _Trip.objects.filter(
            bike=bike,
            status__in=['waiting', 'started', 'ontrip']
        ).select_related('renter__user').first()
        if active_trip:
            notify_user(
                active_trip.renter.user.id,
                'Bike Location',
                '',
                {
                    'notification_type': 'bike_location_update',
                    'trip_id': active_trip.id,
                    'bike_id': bike.id,
                    'latitude': hardware.latitude,
                    'longitude': hardware.longitude,
                    'battery_level': hardware.battery_level,
                }
            )

    return Response({'status': 'ok'})
