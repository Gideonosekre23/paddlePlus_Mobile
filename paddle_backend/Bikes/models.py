from django.db import models
from django.contrib.auth.models import User
from Owner.models import OwnerProfile
from django.conf import settings
import pyotp
import time
import base64
from django.utils import timezone
import os

from django.core.exceptions import ValidationError

def validate_image_size(image):
    max_mb = 5
    if image.size > max_mb * 1024 * 1024:
        raise ValidationError(f'Image file size must be under {max_mb}MB.')

def bike_image_upload_path(instance, filename):
    ext = filename.split('.')[-1]
    filename = f"{instance.owner.id}_{instance.bike_name}_{int(timezone.now().timestamp())}.{ext}"
    return os.path.join('bike_images', str(instance.owner.id), filename)



class BikeHardware(models.Model):
    # Hardware Identification
    serial_number = models.CharField(max_length=100, unique=True, null=True, blank=True)
    factory_key = models.CharField(max_length=64, null=True, blank=True)
    firmware_version = models.CharField(max_length=20, null=True, blank=True)
    
    # Assignment Status
    is_assigned = models.BooleanField(default=False)
    
    # Connection Status
    is_online = models.BooleanField(default=False)
    last_ping = models.DateTimeField(null=True, blank=True)
    signal_strength = models.IntegerField(null=True, blank=True, help_text="Signal strength in dBm")
    
    # Power Management
    battery_level = models.IntegerField(default=100, help_text="Battery percentage 0-100")
    
    # Location Tracking
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    last_location_update = models.DateTimeField(null=True, blank=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        verbose_name = "Bike Hardware"
        verbose_name_plural = "Bike Hardware"
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['serial_number']),
            models.Index(fields=['is_assigned', 'is_online']),
            models.Index(fields=['latitude', 'longitude']),
        ]
    
    def generate_unlock_code(self):
        """Generate TOTP unlock code for Arduino"""
        if not self.serial_number:
            return None
        
        factory_key = settings.TOTP_FACTORY_KEY
        raw_secret = (self.serial_number + factory_key).encode()
        base32_secret = base64.b32encode(raw_secret).decode('utf-8')
        totp = pyotp.TOTP(base32_secret, digits=6, interval=300)
        current_time = int(time.time())
        return totp.at(current_time)

    def verify_unlock_code(self, code):
        """Verify a TOTP unlock code"""
        if not self.serial_number or not code:
            return False
        factory_key = settings.TOTP_FACTORY_KEY
        raw_secret = (self.serial_number + factory_key).encode()
        base32_secret = base64.b32encode(raw_secret).decode('utf-8')
        totp = pyotp.TOTP(base32_secret, digits=6, interval=300)
        return totp.verify(str(code), valid_window=1)

    def update_status(self, battery_level=None, signal_strength=None):
        """Update hardware status with ping"""
        self.last_ping = timezone.now()
        self.is_online = True
        if battery_level is not None:
            self.battery_level = max(0, min(100, battery_level))  # Clamp 0-100
        if signal_strength is not None:
            self.signal_strength = signal_strength
        self.save(update_fields=['last_ping', 'is_online', 'battery_level', 'signal_strength', 'updated_at'])
    
    def update_location(self, latitude, longitude):
        """Update GPS location from Arduino"""
        self.latitude = latitude
        self.longitude = longitude
        self.last_location_update = timezone.now()
        self.save(update_fields=['latitude', 'longitude', 'last_location_update', 'updated_at'])
        
        # Update associated bike location
        if hasattr(self, 'assigned_bike') and self.assigned_bike:
            self.assigned_bike.update_location(latitude, longitude)
    
    def mark_offline(self):
        """Mark hardware as offline"""
        self.is_online = False
        self.save(update_fields=['is_online', 'updated_at'])
    
    def get_connection_status(self):
        """Get detailed connection status"""
        if not self.last_ping:
            return 'never_connected'
        
        time_since_ping = timezone.now() - self.last_ping
        if time_since_ping.total_seconds() > 300:  # 5 minutes
            return 'offline'
        elif time_since_ping.total_seconds() > 120:  # 2 minutes
            return 'poor_connection'
        else:
            return 'online'
    
    def get_battery_status(self):
        """Get battery status with warnings"""
        if self.battery_level >= 50:
            return 'good'
        elif self.battery_level >= 20:
            return 'low'
        else:
            return 'critical'
    
    def __str__(self):
        status = "Assigned" if self.is_assigned else "Unassigned"
        online = "Online" if self.is_online else "Offline"
        return f"Hardware {self.serial_number} ({status}, {online})"


class Bikes(models.Model):
    HARDWARE_STATUS = [
        ('active', 'Active and Ready'),
        ('inactive', 'Inactive or Unavailable'),
        ('maintenance', 'Under Maintenance'),
        ('locked', 'Locked'),
        ('unlocked', 'Unlocked'),
        ('offline', 'Hardware Offline'),
        ('low_battery', 'Low Battery'),
    ]

    BIKE_STATUS = [
        ('available', 'Available for Rent'),
        ('rented', 'Currently Rented'),
        ('reserved', 'Reserved'),
        ('disabled', 'Temporarily Disabled'),
        ('maintenance', 'Under Maintenance'),
    ]

    # Basic Bike Information
    owner = models.ForeignKey(OwnerProfile, on_delete=models.CASCADE, related_name='bikes_owned')
    bike_name = models.CharField(max_length=100)
    brand = models.CharField(max_length=100)
    model = models.CharField(max_length=100)
    color = models.CharField(max_length=50) 
    size = models.CharField(max_length=20)
    year = models.PositiveIntegerField()
    description = models.TextField()

     # Bike Image
    bike_image = models.ImageField(
        upload_to=bike_image_upload_path,
        null=True,
        blank=True,
        validators=[validate_image_size],
        help_text="Upload an image of the bike (max 5MB)"
    )
    
    # Availability Status
    is_available = models.BooleanField(default=False)
    is_active = models.BooleanField(default=False)
    bike_status = models.CharField(max_length=20, choices=BIKE_STATUS, default='disabled')
    
    # Location Data
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    bike_address = models.CharField(max_length=255, null=True, blank=True)
    last_location_update = models.DateTimeField(null=True, blank=True)
    
    # Hardware Integration
    hardware = models.OneToOneField(
        BikeHardware, 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True,
        related_name='assigned_bike'
    )
    hardware_status = models.CharField(max_length=20, choices=HARDWARE_STATUS, default='inactive')
    
    # Lock Status Tracking
    last_unlock_time = models.DateTimeField(null=True, blank=True)
    last_lock_time = models.DateTimeField(null=True, blank=True)
    unlock_code_generated_at = models.DateTimeField(null=True, blank=True)
    
    
    # Business Metrics
    total_earnings = models.DecimalField(

        max_digits=10, 
        decimal_places=2, 
        default=0.00,
        help_text="Total earnings from this specific bike"
    )
    total_trips = models.PositiveIntegerField(default=0)
    total_distance = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=5.00)
    rating_count = models.PositiveIntegerField(default=0)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "Bikes"
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['hardware_status', 'bike_status']),
            models.Index(fields=['latitude', 'longitude']),
            models.Index(fields=['is_available', 'is_active']),
            models.Index(fields=['owner', 'bike_status']),
        ]

    def activate_with_hardware(self, serial_number):
        """Activate bike with scanned hardware QR code"""
        try:
            hardware = BikeHardware.objects.select_for_update().get(
                serial_number=serial_number,
                
                is_assigned=False
            )
            
            # Assign hardware to bike
            hardware.is_assigned = True
            hardware.save()
            
            # Update bike status
            self.hardware = hardware
            self.is_active = True
            self.hardware_status = 'active'
            self.bike_status = 'available'
            self.is_available = True
            self.save()
            
            return True, "Bike activated successfully"
            
        except BikeHardware.DoesNotExist:
            return False, "Invalid hardware credentials"
        except Exception as e:
            return False, f"Activation failed: {str(e)}"

    def generate_unlock_code(self):
        """Generate unlock code for user"""
        if not self.hardware:
            return None
        
        code = self.hardware.generate_unlock_code()
        if code:
            self.unlock_code_generated_at = timezone.now()
            self.save(update_fields=['unlock_code_generated_at'])
        return code

    def verify_unlock_code(self, code):
        """Verify unlock code and update status"""
        if not self.hardware:
            return False
        
        is_valid = self.hardware.verify_unlock_code(code)
        if is_valid:
            self.hardware_status = 'unlocked'
            self.last_unlock_time = timezone.now()
            self.save(update_fields=['hardware_status', 'last_unlock_time', 'updated_at'])
        
        return is_valid

    def lock_bike(self):
        """Lock the bike"""
        if self.hardware_status in ['unlocked', 'active']:
            self.hardware_status = 'locked'
            self.last_lock_time = timezone.now()
            self.save(update_fields=['hardware_status', 'last_lock_time', 'updated_at'])
            return True
        return False

    def update_location(self, latitude, longitude):
        """Update bike location from GPS"""
        self.latitude = latitude
        self.longitude = longitude
        self.last_location_update = timezone.now()
        self.save(update_fields=['latitude', 'longitude', 'last_location_update', 'updated_at'])

    def update_trip_metrics(self, trip_distance, trip_earnings):
        """Update bike metrics after trip completion"""
        self.total_trips += 1
        self.total_distance += trip_distance
        self.total_earnings += trip_earnings
        self.save(update_fields=['total_trips', 'total_distance', 'total_earnings', 'updated_at'])

    def check_hardware_health(self):
        """Check hardware health and update status accordingly"""
        if not self.hardware:
            self.hardware_status = 'inactive'
            self.save(update_fields=['hardware_status', 'updated_at'])
            return
        
        connection_status = self.hardware.get_connection_status()
        battery_status = self.hardware.get_battery_status()
        
        # Update hardware status based on health
        if connection_status == 'offline':
            self.hardware_status = 'offline'
        elif battery_status == 'critical':
            self.hardware_status = 'low_battery'
        elif self.hardware_status in ['offline', 'low_battery'] and connection_status == 'online' and battery_status in ['good', 'low']:
            self.hardware_status = 'active'
        
        self.save(update_fields=['hardware_status', 'updated_at'])

    def get_hardware_status(self):
        """Get detailed hardware status"""
        if not self.hardware:
            return None
        
        return {
            'status': self.hardware_status,
            'battery': self.hardware.battery_level,
            'battery_status': self.hardware.get_battery_status(),
            'connection_status': self.hardware.get_connection_status(),
            'signal_strength': self.hardware.signal_strength,
            'last_unlock': self.last_unlock_time,
            'last_lock': self.last_lock_time,
            'last_ping': self.hardware.last_ping,
            'last_location_update': self.hardware.last_location_update,
            'serial_number': self.hardware.serial_number,
            'is_online': self.hardware.is_online,
            'firmware_version': self.hardware.firmware_version,
        }

    def get_location(self):
        """Get current location"""
        return {
            'latitude': self.latitude,
            'longitude': self.longitude,
            'last_update': self.last_location_update,
        }

    def is_rentable(self):
        """Check if bike is available for rent"""
        return (
            self.is_active and 
            self.is_available and 
            self.bike_status == 'available' and
            self.hardware_status in ['active', 'locked'] and
            self.hardware and 
            self.hardware.get_connection_status() == 'online' and
            self.hardware.get_battery_status() != 'critical'
        )
    
    


    def get_availability_issues(self):
        """Get list of issues preventing rental"""
        issues = []
        
        if not self.is_active:
            issues.append("Bike not activated")
        if not self.is_available:
            issues.append("Bike marked as unavailable")
        if self.bike_status != 'available':
            issues.append(f"Bike status: {self.get_bike_status_display()}")
        if not self.hardware:
            issues.append("No hardware assigned")
        elif self.hardware.get_connection_status() != 'online':
            issues.append("Hardware offline")
        elif self.hardware.get_battery_status() == 'critical':
            issues.append("Critical battery level")
        
        return issues

    def __str__(self):
        return f"{self.brand} {self.model} ({self.bike_name}) - {self.owner.user.username}"
