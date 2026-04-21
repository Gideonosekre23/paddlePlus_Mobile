from math import radians, sin, cos, sqrt, atan2
from django.utils import timezone

from .models import Bikes

def calculate_price(distance, duration_hours):
    base_fare = 2.00
    rate_per_km = 1.50
    rate_per_hour = 10.00
    
    distance_cost = distance * rate_per_km
    duration_cost = duration_hours * rate_per_hour
    
    # Take the higher cost 
    variable_cost = max(distance_cost, duration_cost)
    
    total_price = base_fare + variable_cost
    return round(total_price, 2)

def calculate_distance(lat1, lon1, lat2, lon2):
    R = 6371  # Earth radius in kilometers
    lat1, lon1, lat2, lon2 = map(radians, [float(lat1), float(lon1), float(lat2), float(lon2)])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c

def get_price_estimate(pickup_latitude, pickup_longitude, destination_latitude, destination_longitude, rider_profile, exclude_bike_ids=None):
    available_bikes = Bikes.objects.filter(
        is_available=True,
        is_active=True,
        bike_status='available',
        latitude__isnull=False,
        longitude__isnull=False,
    )
    if exclude_bike_ids:
        available_bikes = available_bikes.exclude(id__in=exclude_bike_ids)
    bikes_with_distance = []

    for bike in available_bikes:
        distance_to_rider = calculate_distance(pickup_latitude, pickup_longitude, bike.latitude, bike.longitude)
        bikes_with_distance.append((bike, distance_to_rider))

    if not bikes_with_distance:
        return None, None, None

    # Sort by distance and pick the closest still-available bike
    bikes_with_distance.sort(key=lambda x: x[1])
    nearest_bike, distance_to_bike = None, None
    for bike, dist in bikes_with_distance:
        # Re-verify availability at selection time to guard against race conditions
        if Bikes.objects.filter(pk=bike.pk, is_available=True, is_active=True, bike_status='available').exists():
            nearest_bike, distance_to_bike = bike, dist
            break

    if nearest_bike is None:
        return None, None, None

    trip_distance = calculate_distance(pickup_latitude, pickup_longitude, destination_latitude, destination_longitude)
    estimated_price = calculate_price(distance=trip_distance, duration_hours=trip_distance / 30)

    return nearest_bike, distance_to_bike, estimated_price
