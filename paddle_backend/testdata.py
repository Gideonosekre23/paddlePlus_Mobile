import os
import django
from decimal import Decimal
import random
from datetime import datetime, timedelta

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'paddle_backend.settings')
django.setup()

from django.contrib.auth.models import User
from django.utils import timezone
from Rider.models import UserProfile
from Owner.models import OwnerProfile
from Bikes.models import Bikes, BikeHardware
from Trip.models import Trip

def create_complete_test_data():
    print("🗑️ Clearing existing data...")
    
    # Clear in correct order (relationships first)
    Trip.objects.all().delete()
    Bikes.objects.all().delete()
    BikeHardware.objects.all().delete()
    UserProfile.objects.all().delete()
    OwnerProfile.objects.all().delete()
    User.objects.filter(is_superuser=False).delete()
    
    print("✅ Database cleared!")
    
    # Timișoara locations for bikes (hardware + bike same location)
    bike_locations = [
        (45.7494, 21.2272, "Piața Victoriei"),
        (45.7605, 21.2200, "Parcul Rozelor"),
        (45.7547, 21.2377, "Iulius Mall"),
        (45.7407, 21.2257, "Universitatea de Vest"),
        (45.7583, 21.2255, "Catedrala Metropolitană"),
        (45.7456, 21.2089, "Stadionul Dan Păltinișanu"),
    ]
    
    # Rider locations
    rider_locations = [
        (45.7520, 21.2280, "Strada Memorandului"),
        (45.7480, 21.2350, "Strada Eminescu"),
        (45.7600, 21.2180, "Strada Roses"),
        (45.7420, 21.2240, "Campus UVT"),
        (45.7560, 21.2260, "Centrul Vechi"),
    ]
    
    print("👥 Creating 5 verified riders...")
    riders = []
    for i in range(1, 6):
        lat, lng, area = rider_locations[i-1]
        
        user = User.objects.create_user(
            username=f'rider{i}',
            email=f'rider{i}@test.com',
            password='password123',
            first_name=f'Rider{i}',
            last_name='User'
        )
        
        rider = UserProfile.objects.create(
            user=user,
            cpn=f'123456789012{i}',
            phone_number=f'+4073123456{i}',
            address=f'{area}, Timișoara',
            verification_status='verified',
            latitude=lat,
            longitude=lng
        )
        riders.append(rider)
        print(f"✅ Created {user.username} at {area}")
    
    print("\n🏠 Creating 5 verified owners...")
    owners = []
    for i in range(1, 6):
        user = User.objects.create_user(
            username=f'owner{i}',
            email=f'owner{i}@test.com',
            password='password123',
            first_name=f'Owner{i}',
            last_name='BikeOwner'
        )
        
        owner = OwnerProfile.objects.create(
            user=user,
            cpn=f'987654321012{i}',
            phone_number=f'+4072123456{i}',
            verification_status='verified',
            total_earnings=Decimal('0.00'),
            latitude=45.7494 + (i * 0.002),
            longitude=21.2272 + (i * 0.002)
        )
        owners.append(owner)
        print(f"✅ Created {user.username}")
    
    print("\n🔧 Creating hardware and bikes...")
    bikes = []
    bike_data = [
        # Owner 1: 3 bikes
        ('City Explorer', 'Trek', 'FX 3', 'Blue', 'M', 2023),
        ('Mountain Beast', 'Trek', 'X-Caliber', 'Red', 'L', 2023),
        ('Road Runner', 'Trek', 'Domane', 'Black', 'M', 2024),
        # Owner 2: 2 bikes  
        ('Urban Cruiser', 'Specialized', 'Sirrus', 'White', 'M', 2023),
        ('Trail Master', 'Specialized', 'Rockhopper', 'Green', 'L', 2024),
        # Owner 3: 1 bike
        ('City Comfort', 'Giant', 'Escape', 'Yellow', 'M', 2023),
    ]
    
    bike_owners = [0, 0, 0, 1, 1, 2]  # Owner distribution
    
    for i, (name, brand, model, color, size, year) in enumerate(bike_data):
        lat, lng, location = bike_locations[i]
        owner = owners[bike_owners[i]]
        
        # Create hardware (lock) first
        hardware = BikeHardware.objects.create(
            serial_number=f'HW_{brand.upper()}_{i+1:03d}',
            factory_key=f'FK_{brand.upper()}_2024_{i+1:03d}',
            is_assigned=True,
            battery_level=random.randint(75, 95),
            latitude=lat,  # 🔒 Lock location
            longitude=lng  # 🔒 Lock location
        )
        
        # Create bike at SAME location
        bike = Bikes.objects.create(
            owner=owner,
            bike_name=name,
            brand=brand,
            model=model,
            color=color,
            size=size,
            year=year,
            description=f'{brand} {model} - Perfect for city rides',
            is_available=True,
            is_active=True,
            bike_status='available',
            latitude=lat,    # 🚴 Bike location (same as lock)
            longitude=lng,   # 🚴 Bike location (same as lock)
            hardware=hardware,  # 🔗 Linked to lock
            hardware_status='active',
            total_trips=0,
            total_distance=Decimal('0.00'),
            rating=Decimal('5.00'),
            total_earnings=Decimal('0.00')
        )
        bikes.append(bike)
        print(f"✅ Created {name} ({brand} {model}) at {location} for {owner.user.username}")
    
    print(f"\n🛣️ Creating 15 trips (3 per rider)...")
    
    # Trip destinations in Timișoara
    destinations = [
        (45.7600, 21.2150, "Parcul Central"),
        (45.7520, 21.2400, "Shopping City"),
        (45.7450, 21.2100, "Gara de Nord"),
        (45.7580, 21.2300, "Piața Unirii"),
        (45.7480, 21.2200, "Bega Mall"),
    ]
    
    trip_count = 0
    for rider_idx, rider in enumerate(riders):
        print(f"\n👤 Creating trips for {rider.user.username}:")
        
        for trip_num in range(3):  # 3 trips per rider
            # Select bike (distribute across available bikes)
            bike = bikes[trip_count % len(bikes)]
            owner = bike.owner
            
            # Random destination
            dest_lat, dest_lng, dest_name = random.choice(destinations)
            
            # Random trip details
            distance = round(random.uniform(1.5, 8.0), 2)
            base_price = distance * random.uniform(2.5, 4.0)
            price = round(base_price, 2)
            commission = round(price * 0.15, 2)  # 15% commission
            owner_payout = round(price - commission, 2)
            
            # Trip timing (random past trips)
            days_ago = random.randint(1, 30)
            start_time = timezone.now() - timedelta(days=days_ago, hours=random.randint(8, 20))
            duration_minutes = random.randint(15, 90)
            end_time = start_time + timedelta(minutes=duration_minutes)
            
            # Create trip
            trip = Trip.objects.create(
                renter=rider,
                bike_owner=owner,
                bike=bike,
                
                # Locations
                origin_latitude=rider.latitude,
                origin_longitude=rider.longitude,
                origin_address=rider.address,
                destination_latitude=dest_lat,
                destination_longitude=dest_lng,
                destination_address=f"{dest_name}, Timișoara",
                
                # Trip details
                distance=Decimal(str(distance)),
                price=Decimal(str(price)),
                payment_type=random.choice(['card', 'cash']),
                status='completed',
                
                # Payment
                payment_status='completed',
                commission_amount=Decimal(str(commission)),
                owner_payout=Decimal(str(owner_payout)),
                payment_processed_at=end_time,
                
                # Timing
                start_time=start_time,
                end_time=end_time,
            )
            
            # Update bike earnings and stats
            bike.total_earnings += trip.owner_payout
            bike.total_trips += 1
            bike.total_distance += trip.distance
            bike.save()
            
            # Update owner earnings
            owner.total_earnings += trip.owner_payout
            owner.save()
            
            trip_count += 1
            print(f"  ✅ Trip {trip_num + 1}: {bike.bike_name} → {dest_name} ({distance}km, {price} RON)")
    
    print("\n📊 SUMMARY:")
    print(f"👥 Riders: {UserProfile.objects.count()}")
    print(f"🏠 Owners: {OwnerProfile.objects.count()}")
    print(f"🔧 Hardware: {BikeHardware.objects.count()}")
    print(f"🚴 Bikes: {Bikes.objects.count()}")
    print(f"🛣️ Trips: {Trip.objects.count()}")
    
    print("\n💰 OWNER EARNINGS:")
    for owner in OwnerProfile.objects.all():
        bike_count = owner.bikes_owned.count()
        print(f"  {owner.user.username}: {owner.total_earnings} RON ({bike_count} bikes)")
    
    print("\n🚴 BIKE EARNINGS:")
    for bike in Bikes.objects.all():
        print(f"  {bike.bike_name}: {bike.total_earnings} RON ({bike.total_trips} trips)")
    
    print("\n🎉 Test data creation complete!")

if __name__ == "__main__":
    create_complete_test_data()
