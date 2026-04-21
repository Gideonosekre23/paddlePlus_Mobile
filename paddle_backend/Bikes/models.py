from django.db import models
from django.contrib.auth.models import User
from Owner.models import OwnerProfile
import pyotp
from django.utils import timezone

class BikeHardware(models.Model):
    serial_number = models.CharField(max_length=100, unique=True, null=True, blank=True)
    factory_key = models.CharField(max_length=64, null=True, blank=True)
    is_assigned = models.BooleanField(default=False)
    last_ping = models.DateTimeField(null=True, blank=True)
    battery_level = models.IntegerField(default=100)
    last_location_update = models.DateTimeField(null=True, blank=True)
    latitude = models.FloatField(null=True)
    longitude = models.FloatField(null=True)

    def generate_unlock_code(self):
        current_time = int(timezone.now().timestamp())
        secret = f"{self.serial_number}{self.factory_key}"
        totp = pyotp.TOTP(secret, interval=30)
        return totp.at(current_time)

    def update_status(self, battery_level=None):
        self.last_ping = timezone.now()
        if battery_level:
            self.battery_level = battery_level
        self.save()

class Bikes(models.Model):
    HARDWARE_STATUS = [
        ('active', 'Active and Ready'),
        ('inactive', 'Inactive or Unavailable'),
        ('maintenance', 'Under Maintenance'),
        ('locked', 'Locked'),
        ('unlocked', 'Unlocked')
    ]

    BIKE_STATUS = [
        ('available', 'Available for Rent'),
        ('rented', 'Currently Rented'),
        ('reserved', 'Reserved'),
        ('disabled', 'Temporarily Disabled')
    ]

    owner = models.ForeignKey(OwnerProfile, on_delete=models.CASCADE, related_name='bikes_owned')
    bike_name = models.CharField(max_length=100)
    brand = models.CharField(max_length=100)
    model = models.CharField(max_length=100)
    color = models.CharField(max_length=50)
    size = models.CharField(max_length=20)
    year = models.PositiveIntegerField()
    description = models.TextField()
    
    is_available = models.BooleanField(default=False)
    is_active = models.BooleanField(default=False)
    bike_status = models.CharField(max_length=20, choices=BIKE_STATUS, default='disabled')
    
    latitude = models.FloatField(null=True)
    longitude = models.FloatField(null=True)
    last_location_update = models.DateTimeField(auto_now=True)
    
    hardware = models.OneToOneField(BikeHardware, on_delete=models.SET_NULL, null=True, related_name='assigned_bike')
    hardware_status = models.CharField(max_length=20, choices=HARDWARE_STATUS, default='inactive')
    last_unlock_time = models.DateTimeField(null=True, blank=True)
    last_lock_time = models.DateTimeField(null=True, blank=True)
    
    total_trips = models.PositiveIntegerField(default=0)
    total_distance = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=5.00)
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "Bikes"
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['hardware_status', 'bike_status']),
            models.Index(fields=['latitude', 'longitude']),
        ]

    def activate_with_hardware(self, scanned_data):
        try:
            hardware = BikeHardware.objects.select_for_update().get(
                serial_number=scanned_data['serial'],
                factory_key=scanned_data['key'],
                is_assigned=False
            )
            hardware.is_assigned = True
            hardware.save()
            self.hardware = hardware
            self.is_active = True
            self.hardware_status = 'active'
            self.bike_status = 'available'
            self.is_available = True
            self.save()
            return True
        except BikeHardware.DoesNotExist:
            return False

    def verify_unlock_code(self, code):
        if self.hardware:
            is_valid = self.hardware.verify_unlock_code(code)
            if is_valid:
                self.hardware_status = 'unlocked'
                self.last_unlock_time = timezone.now()
                self.save()
            return is_valid
        return False

    def lock_bike(self):
        if self.hardware_status == 'unlocked':
            self.hardware_status = 'locked'
            self.last_lock_time = timezone.now()
            self.save()
            return True
        return False

    def update_location(self, latitude, longitude):
        self.latitude = latitude
        self.longitude = longitude
        self.last_location_update = timezone.now()
        self.save()

    def update_trip_metrics(self, trip_distance):
        self.total_trips += 1
        self.total_distance += trip_distance
        self.save()

    def get_hardware_status(self):
        if self.hardware:
            return {
                'status': self.hardware_status,
                'battery': self.hardware.battery_battery_level,
                'last_unlock': self.last_unlock_time,
                'last_lock': self.last_lock_time,
                'last_ping': self.hardware.last_ping,
                'serial_number': self.hardware.serial_number
            }
        return None

    def __str__(self):
        return f"{self.brand} {self.model} owned by {self.owner.user.username}"
