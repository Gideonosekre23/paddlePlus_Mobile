"""
Seed command: 10 owners + 10 bikes in Timișoara (Iosefin neighbourhood focus).

Usage:
    python manage.py seed_timisoara_bikes
    python manage.py seed_timisoara_bikes --clear   # wipe seeded data first
"""

import os
import random
import string
import requests
from io import BytesIO
from django.core.management.base import BaseCommand
from django.core.files.base import ContentFile
from django.contrib.auth.models import User
from django.conf import settings
from Owner.models import OwnerProfile
from Bikes.models import Bikes, BikeHardware


# ---------------------------------------------------------------------------
# Seed data
# ---------------------------------------------------------------------------

OWNERS = [
    {
        "username": "owner_andrei_pop",
        "first_name": "Andrei",
        "last_name": "Pop",
        "email": "andrei.pop@paddleplus.ro",
        "phone": "+40721100001",
        "cpn": "1850312354789",
        "lat": 45.7540,
        "lng": 21.2180,
    },
    {
        "username": "owner_ioana_moldovan",
        "first_name": "Ioana",
        "last_name": "Moldovan",
        "email": "ioana.moldovan@paddleplus.ro",
        "phone": "+40721100002",
        "cpn": "2900512354890",
        "lat": 45.7530,
        "lng": 21.2150,
    },
    {
        "username": "owner_mihai_ionescu",
        "first_name": "Mihai",
        "last_name": "Ionescu",
        "email": "mihai.ionescu@paddleplus.ro",
        "phone": "+40721100003",
        "cpn": "1780612354901",
        "lat": 45.7560,
        "lng": 21.2200,
    },
    {
        "username": "owner_elena_popa",
        "first_name": "Elena",
        "last_name": "Popa",
        "email": "elena.popa@paddleplus.ro",
        "phone": "+40721100004",
        "cpn": "2820312355012",
        "lat": 45.7490,
        "lng": 21.2100,
    },
    {
        "username": "owner_radu_dima",
        "first_name": "Radu",
        "last_name": "Dima",
        "email": "radu.dima@paddleplus.ro",
        "phone": "+40721100005",
        "cpn": "1960712355123",
        "lat": 45.7570,
        "lng": 21.2250,
    },
    {
        "username": "owner_maria_stan",
        "first_name": "Maria",
        "last_name": "Stan",
        "email": "maria.stan@paddleplus.ro",
        "phone": "+40721100006",
        "cpn": "2880212355234",
        "lat": 45.7510,
        "lng": 21.2130,
    },
    {
        "username": "owner_bogdan_rusu",
        "first_name": "Bogdan",
        "last_name": "Rusu",
        "email": "bogdan.rusu@paddleplus.ro",
        "phone": "+40721100007",
        "cpn": "1870112355345",
        "lat": 45.7550,
        "lng": 21.2170,
    },
    {
        "username": "owner_cristina_luca",
        "first_name": "Cristina",
        "last_name": "Luca",
        "email": "cristina.luca@paddleplus.ro",
        "phone": "+40721100008",
        "cpn": "2910412355456",
        "lat": 45.7480,
        "lng": 21.2080,
    },
    {
        "username": "owner_tudor_barbu",
        "first_name": "Tudor",
        "last_name": "Barbu",
        "email": "tudor.barbu@paddleplus.ro",
        "phone": "+40721100009",
        "cpn": "1930812355567",
        "lat": 45.7600,
        "lng": 21.2300,
    },
    {
        "username": "owner_diana_gheorghe",
        "first_name": "Diana",
        "last_name": "Gheorghe",
        "email": "diana.gheorghe@paddleplus.ro",
        "phone": "+40721100010",
        "cpn": "2860512355678",
        "lat": 45.7520,
        "lng": 21.2160,
    },
]

# Iosefin-focused coordinates (lat ~45.752, lng ~21.2165)
BIKES = [
    # --- Iosefin cluster (nearest to user) ---
    {
        "bike_name": "City Cruiser Iosefin",
        "brand": "Trek",
        "model": "FX 3",
        "color": "Matte Blue",
        "size": "M",
        "year": 2023,
        "description": "Lightweight city bike, perfect for urban commutes. 21-speed Shimano gears, front suspension, and comfortable saddle.",
        "lat": 45.7518,
        "lng": 21.2158,
        "address": "Str. Iosefin 12, Timișoara",
        "is_active": True,
        "is_available": True,
        "bike_status": "available",
        "hardware_status": "active",
        "battery": 92,
        "total_trips": 34,
        "total_distance": "187.50",
        "rating": "4.80",
        "owner_index": 0,
    },
    {
        "bike_name": "Green Wheel Iosefin",
        "brand": "Giant",
        "model": "Escape 3",
        "color": "Forest Green",
        "size": "L",
        "year": 2022,
        "description": "Versatile hybrid bike suitable for both city and light trail. Disc brakes and ergonomic grips.",
        "lat": 45.7525,
        "lng": 21.2172,
        "address": "Piața Iosefin 3, Timișoara",
        "is_active": True,
        "is_available": True,
        "bike_status": "available",
        "hardware_status": "active",
        "battery": 87,
        "total_trips": 51,
        "total_distance": "312.20",
        "rating": "4.90",
        "owner_index": 1,
    },
    {
        "bike_name": "Iosefin Swift",
        "brand": "Cannondale",
        "model": "Quick 4",
        "color": "Graphite Grey",
        "size": "S",
        "year": 2023,
        "description": "Fast and nimble city bike with puncture-resistant tyres and integrated rear rack.",
        "lat": 45.7512,
        "lng": 21.2145,
        "address": "Str. Brâncoveanu 7, Timișoara",
        "is_active": True,
        "is_available": True,
        "bike_status": "available",
        "hardware_status": "active",
        "battery": 76,
        "total_trips": 28,
        "total_distance": "145.80",
        "rating": "4.70",
        "owner_index": 2,
    },
    {
        "bike_name": "Iosefin Commuter",
        "brand": "Specialized",
        "model": "Sirrus 2.0",
        "color": "Pearl White",
        "size": "M",
        "year": 2022,
        "description": "Smooth-rolling commuter with fenders included. Great for all weather conditions in the city.",
        "lat": 45.7531,
        "lng": 21.2162,
        "address": "Str. Mangalia 4, Timișoara",
        "is_active": True,
        "is_available": True,
        "bike_status": "available",
        "hardware_status": "active",
        "battery": 95,
        "total_trips": 62,
        "total_distance": "423.60",
        "rating": "4.95",
        "owner_index": 3,
    },
    # --- Nearby Timișoara clusters ---
    {
        "bike_name": "Fabric E-Cruiser",
        "brand": "Cube",
        "model": "Touring Hybrid ONE",
        "color": "Midnight Black",
        "size": "L",
        "year": 2023,
        "description": "E-assist hybrid with 80km range. Bosch mid-motor and integrated lights front and rear.",
        "lat": 45.7548,
        "lng": 21.2195,
        "address": "Bd. Republicii 22, Timișoara",
        "is_active": True,
        "is_available": True,
        "bike_status": "available",
        "hardware_status": "active",
        "battery": 88,
        "total_trips": 19,
        "total_distance": "98.40",
        "rating": "4.85",
        "owner_index": 4,
    },
    {
        "bike_name": "Piața Unirii Racer",
        "brand": "Scott",
        "model": "Sub Cross 10",
        "color": "Cobalt Blue",
        "size": "M",
        "year": 2021,
        "description": "Lightweight trekking bike, 27-speed gears. Recently serviced and ready for long city rides.",
        "lat": 45.7558,
        "lng": 21.2258,
        "address": "Piața Unirii 1, Timișoara",
        "is_active": True,
        "is_available": True,
        "bike_status": "available",
        "hardware_status": "active",
        "battery": 71,
        "total_trips": 45,
        "total_distance": "267.30",
        "rating": "4.60",
        "owner_index": 5,
    },
    {
        "bike_name": "Fabric Hill Topper",
        "brand": "Merida",
        "model": "Big.Seven 20",
        "color": "Burnt Orange",
        "size": "XL",
        "year": 2022,
        "description": "Mountain-ready hardtail also comfortable on city streets. Hydraulic disc brakes.",
        "lat": 45.7565,
        "lng": 21.2228,
        "address": "Str. Mihai Viteazu 15, Timișoara",
        "is_active": True,
        "is_available": False,
        "bike_status": "rented",
        "hardware_status": "unlocked",
        "battery": 63,
        "total_trips": 77,
        "total_distance": "589.10",
        "rating": "4.75",
        "owner_index": 6,
    },
    {
        "bike_name": "Cetate Classic",
        "brand": "Peugeot",
        "model": "LC01 D7",
        "color": "Cream White",
        "size": "M",
        "year": 2020,
        "description": "Classic Dutch-style city bike. Step-through frame, basket included, 7-speed Shimano.",
        "lat": 45.7498,
        "lng": 21.2108,
        "address": "Str. Oituz 9, Timișoara",
        "is_active": True,
        "is_available": True,
        "bike_status": "available",
        "hardware_status": "active",
        "battery": 100,
        "total_trips": 103,
        "total_distance": "812.45",
        "rating": "4.65",
        "owner_index": 7,
    },
    {
        "bike_name": "Ronaț Speed",
        "brand": "Focus",
        "model": "Planet 2.0",
        "color": "Neon Yellow",
        "size": "S",
        "year": 2023,
        "description": "Sporty fitness bike with 28-inch wheels and carbon fork. Very fast on flat city roads.",
        "lat": 45.7488,
        "lng": 21.2082,
        "address": "Str. Ronaț 5, Timișoara",
        "is_active": False,
        "is_available": False,
        "bike_status": "disabled",
        "hardware_status": "maintenance",
        "battery": 45,
        "total_trips": 12,
        "total_distance": "58.20",
        "rating": "4.50",
        "owner_index": 8,
    },
    {
        "bike_name": "Fabric Blumenau Glider",
        "brand": "Orbea",
        "model": "Vector 30",
        "color": "Dusty Rose",
        "size": "M",
        "year": 2022,
        "description": "Elegant city tourer with swept-back handlebars and leather saddle. Smooth 8-speed gearset.",
        "lat": 45.7607,
        "lng": 21.2312,
        "address": "Str. Blumenau 3, Timișoara",
        "is_active": True,
        "is_available": True,
        "bike_status": "available",
        "hardware_status": "active",
        "battery": 82,
        "total_trips": 39,
        "total_distance": "218.75",
        "rating": "4.80",
        "owner_index": 9,
    },
]

# Picsum portrait IDs for distinct faces (300×300)
PORTRAIT_IDS = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
# Picsum bike/city IDs (600×400)
BIKE_PHOTO_IDS = [11, 22, 33, 44, 55, 66, 77, 88, 99, 110]


def _download_image(url: str, filename: str) -> ContentFile | None:
    try:
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
        return ContentFile(resp.content, name=filename)
    except Exception as exc:
        print(f"    [WARN]  Could not download {url}: {exc}")
        return None


def _random_serial() -> str:
    return "PP" + "".join(random.choices(string.digits, k=8))


def _random_factory_key() -> str:
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=32))


class Command(BaseCommand):
    help = "Seed 10 owners and 10 bikes in Timișoara (Iosefin focus)"

    def add_arguments(self, parser):
        parser.add_argument(
            "--clear",
            action="store_true",
            help="Remove previously seeded users/bikes before seeding",
        )

    def handle(self, *args, **options):
        if options["clear"]:
            self._clear_seeded()

        self.stdout.write(self.style.MIGRATE_HEADING("[SEED]  Seeding Timisoara bikes..."))

        created_owners: list[OwnerProfile] = []

        # ---------------------------------------------------------------
        # 1. Create owners
        # ---------------------------------------------------------------
        for i, od in enumerate(OWNERS):
            if User.objects.filter(username=od["username"]).exists():
                user = User.objects.get(username=od["username"])
                profile = user.owner_profile
                self.stdout.write(f"  --  Owner already exists: {od['username']}")
                created_owners.append(profile)
                continue

            user = User.objects.create_user(
                username=od["username"],
                email=od["email"],
                password="PaddleSeed@2025",
                first_name=od["first_name"],
                last_name=od["last_name"],
            )

            profile = OwnerProfile(
                user=user,
                cpn=od["cpn"],
                phone_number=od["phone"],
                latitude=od["lat"],
                longitude=od["lng"],
                verification_status="verified",
                verification_session_id=f"vs_seed_{i:04d}",
            )

            # Download profile picture
            pic_url = f"https://picsum.photos/id/{PORTRAIT_IDS[i]}/300/300"
            img_file = _download_image(pic_url, f"owner_{i+1}_profile.jpg")
            if img_file:
                profile.profile_picture.save(f"owner_{i+1}_profile.jpg", img_file, save=False)
            else:
                # Write a tiny 1×1 white JPEG as fallback
                fallback = _minimal_jpeg()
                profile.profile_picture.save(f"owner_{i+1}_profile.jpg",
                                             ContentFile(fallback, name=f"owner_{i+1}_profile.jpg"),
                                             save=False)

            profile.save()
            created_owners.append(profile)
            self.stdout.write(self.style.SUCCESS(f"  [OK]  Owner created: {od['first_name']} {od['last_name']}"))

        # ---------------------------------------------------------------
        # 2. Create bikes + hardware
        # ---------------------------------------------------------------
        for i, bd in enumerate(BIKES):
            owner = created_owners[bd["owner_index"]]

            if Bikes.objects.filter(bike_name=bd["bike_name"]).exists():
                self.stdout.write(f"  --  Bike already exists: {bd['bike_name']}")
                continue

            # Hardware
            serial = _random_serial()
            hardware = BikeHardware.objects.create(
                serial_number=serial,
                factory_key=_random_factory_key(),
                is_assigned=True,
                battery_level=bd["battery"],
                latitude=bd["lat"],
                longitude=bd["lng"],
            )

            bike = Bikes(
                owner=owner,
                bike_name=bd["bike_name"],
                brand=bd["brand"],
                model=bd["model"],
                color=bd["color"],
                size=bd["size"],
                year=bd["year"],
                description=bd["description"],
                is_active=bd["is_active"],
                is_available=bd["is_available"],
                bike_status=bd["bike_status"],
                hardware=hardware,
                hardware_status=bd["hardware_status"],
                latitude=bd["lat"],
                longitude=bd["lng"],
                bike_address=bd["address"],
                total_trips=bd["total_trips"],
                total_distance=bd["total_distance"],
                rating=bd["rating"],
            )

            # Download bike image
            photo_url = f"https://picsum.photos/id/{BIKE_PHOTO_IDS[i]}/600/400"
            img_file = _download_image(photo_url, f"bike_{i+1}.jpg")
            if img_file:
                bike.bike_image.save(f"bike_{i+1}.jpg", img_file, save=False)
            else:
                fallback = _minimal_jpeg()
                bike.bike_image.save(f"bike_{i+1}.jpg",
                                     ContentFile(fallback, name=f"bike_{i+1}.jpg"),
                                     save=False)

            bike.save()
            status_label = "[available]" if bd["is_active"] and bd["is_available"] else ("[inactive]" if not bd["is_active"] else "[rented]")
            self.stdout.write(
                self.style.SUCCESS(
                    f"  [OK]  {status_label} Bike created: {_safe(bd['bike_name'])} "
                    f"({bd['brand']} {bd['model']}) - {bd['bike_status']}"
                )
            )

        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS("[DONE]  Seeding complete!"))
        self.stdout.write(f"   Owners : {OwnerProfile.objects.count()} total")
        self.stdout.write(f"   Bikes  : {Bikes.objects.count()} total")
        self.stdout.write("")
        self.stdout.write("   Default owner password: PaddleSeed@2025")

    def _clear_seeded(self):
        self.stdout.write(self.style.WARNING("[CLEAR]  Clearing seeded data..."))
        usernames = [o["username"] for o in OWNERS]
        users = User.objects.filter(username__in=usernames)
        count = users.count()
        users.delete()
        bike_names = [b["bike_name"] for b in BIKES]
        b_count, _ = Bikes.objects.filter(bike_name__in=bike_names).delete()
        self.stdout.write(self.style.WARNING(f"   Removed {count} users and {b_count} bikes."))


def _safe(s: str) -> str:
    """Replace non-ASCII chars so Windows CP1252 console doesn't choke."""
    return s.encode("ascii", "replace").decode("ascii")


def _minimal_jpeg() -> bytes:
    """Return a valid 1×1 white JPEG so ImageField validation passes."""
    return (
        b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
        b"\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t"
        b"\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a"
        b"\x1f\x1e\x1d\x1a\x1c\x1c $.' \",#\x1c\x1c(7),01444\x1f'9=82<.342\x1e"
        b"=\x16\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00\xff\xc4"
        b"\x00\x1f\x00\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00\x00\x00"
        b"\x00\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\t\n\x0b"
        b"\xff\xc4\x00\xb5\x10\x00\x02\x01\x03\x03\x02\x04\x03\x05\x05"
        b"\x04\x04\x00\x00\x01}\x01\x02\x03\x00\x04\x11\x05\x12!1A\x06"
        b"\x13Qa\x07\"q\x142\x81\x91\xa1\x08#B\xb1\xc1\x15R\xd1\xf0$3br"
        b"\x82\t\n\x16\x17\x18\x19\x1a%&'()*456789:CDEFGHIJSTUVWXYZ"
        b"cdefghijstuvwxyz\x83\x84\x85\x86\x87\x88\x89\x8a\x92\x93\x94"
        b"\x95\x96\x97\x98\x99\x9a\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa"
        b"\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xc2\xc3\xc4\xc5\xc6\xc7"
        b"\xc8\xc9\xca\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xe1\xe2\xe3"
        b"\xe4\xe5\xe6\xe7\xe8\xe9\xea\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8"
        b"\xf9\xfa\xff\xda\x00\x08\x01\x01\x00\x00?\x00\xfb\xd4P\x00\x00"
        b"\x00\x1f\xff\xd9"
    )
