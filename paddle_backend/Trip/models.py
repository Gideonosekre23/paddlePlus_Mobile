from django.db import models
from django.contrib.auth.models import User
from Rider.models import UserProfile
from Owner.models import OwnerProfile
from Bikes.models import Bikes
from decimal import Decimal
import pyotp
from datetime import datetime
from django.utils import timezone
from django.apps import apps 

class Trip(models.Model):
    STATUS_CHOICES = [
        ('waiting', 'Waiting'),      # User paid, walking to bike
        ('started', 'Started'),      # User at bike, trip started
        ('ontrip', 'On Trip'),       # User riding
        ('completed', 'Completed'),  # Trip finished
        ('canceled', 'Canceled'),    # Trip canceled
    ]

    PAYMENT_STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('processing', 'Processing'),
        ('completed', 'Completed'),
        ('failed', 'Failed')
    ]

    COMMISSION_RATE = Decimal('0.20')  # 20% platform commission

    # Core trip information
    renter = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='trips_taken')
    bike_owner = models.ForeignKey(OwnerProfile, on_delete=models.CASCADE, related_name='trips_given')
    bike = models.ForeignKey(Bikes, on_delete=models.CASCADE)
    
    # Trip timing
    trip_date = models.DateTimeField(auto_now_add=True)
    start_time = models.DateTimeField(null=True, blank=True)  
    end_time = models.DateTimeField(null=True, blank=True)    
    
    # Location data
    origin_latitude = models.FloatField(null=True, blank=True)     
    origin_longitude = models.FloatField(null=True, blank=True)
    destination_latitude = models.FloatField(null=True, blank=True)  
    destination_longitude = models.FloatField(null=True, blank=True)
    origin_address = models.CharField(max_length=255, null=True, blank=True)
    destination_address = models.CharField(max_length=255, null=True, blank=True)
    
    # Trip data
    distance = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    payment_type = models.CharField(max_length=100)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='waiting')
    
    # Payment and Commission fields
    payment_status = models.CharField(
        max_length=20, 
        choices=PAYMENT_STATUS_CHOICES, 
        default='pending'
    )
    commission_amount = models.DecimalField(
        max_digits=10, 
        decimal_places=2, 
        null=True, 
        blank=True
    )
    owner_payout = models.DecimalField(
        max_digits=10, 
        decimal_places=2, 
        null=True, 
        blank=True
    )
    payment_processed_at = models.DateTimeField(null=True, blank=True)
    
    # Stripe payment tracking
    payment_intent_id = models.CharField(max_length=255, null=True, blank=True)
    stripe_transfer_id = models.CharField(max_length=255, null=True, blank=True)
    
    # Unlock code fields
    unlock_code = models.CharField(max_length=6, blank=True)
    code_generated_at = models.DateTimeField(null=True, blank=True)
    
    # Rating
    rider_rating = models.PositiveSmallIntegerField(null=True, blank=True)
    rider_review = models.TextField(null=True, blank=True)
    owner_rating = models.PositiveSmallIntegerField(null=True, blank=True)
    owner_review = models.TextField(null=True, blank=True)

    # Legacy fields (keep for compatibility)
    trip_canceled = models.BooleanField(default=False)
    origin_map = models.ImageField(upload_to='trip_maps/', null=True, blank=True)
    destination_map = models.ImageField(upload_to='trip_maps/', null=True, blank=True)

    def save(self, *args, **kwargs):
        """Override save to manage bike availability"""
        # When trip is created with 'waiting' status, mark bike as unavailable
        if self.status == 'waiting' and not self.pk:  
            self.bike.is_available = False
            self.bike.save()
        
        # When trip status changes, manage bike availability
        if self.pk:  
            try:
                old_trip = Trip.objects.get(pk=self.pk)
                # If trip moves from active status to completed/canceled, free the bike
                if old_trip.status in ['waiting', 'started', 'ontrip'] and self.status in ['completed', 'canceled']:
                    self.bike.is_available = True
                    self.bike.save()
            except Trip.DoesNotExist:
                pass
        
        super().save(*args, **kwargs)

    def process_unlock_status(self, is_unlocked):
        try:
            ChatRoom = apps.get_model('chat', 'ChatRoom')
            Message = apps.get_model('chat', 'Message')
            chat_room = ChatRoom.objects.get(trip=self)
            content = "🔓 Bike has been unlocked successfully!" if is_unlocked else "🔒 Bike has been locked"
            Message.objects.create(
                chat_room=chat_room,
                sender=self.bike_owner.user,
                content=content
            )
        except ChatRoom.DoesNotExist:
            pass

    def calculate_commission(self):
        
        self.commission_amount = self.price * self.COMMISSION_RATE
        self.owner_payout = self.price - self.commission_amount
        self.save()

    def process_payment(self):
      
        try:
            self.payment_status = 'processing'
            self.calculate_commission()
            self.payment_status = 'completed'
            self.payment_processed_at = timezone.now()
            self.save()
            return True
        except Exception as e:
            self.payment_status = 'failed'
            self.save()
            raise e

    def start_trip(self):
        
        if self.status != 'waiting':
            raise ValueError("Trip must be 'waiting' to start")
        
        self.status = 'started'
        self.start_time = timezone.now()
        
        # Generate unlock code
        if hasattr(self.bike, 'hardware'):
            self.unlock_code = self.bike.hardware.generate_unlock_code()
            self.code_generated_at = timezone.now()
        
        self.save()

    def begin_riding(self):
       
        if self.status != 'started':
            raise ValueError("Trip must be 'started' to begin riding")
        
        self.status = 'ontrip'
        self.save()

    def complete_trip(self):
        
        if self.status not in ['started', 'ontrip']:
            raise ValueError("Trip must be 'started' or 'ontrip' to complete")
        
        self.status = 'completed'
        self.end_time = timezone.now()
        
        # Ensure payment is processed
        if self.payment_status != 'completed':
            self.process_payment()
        
        self.save()

    def cancel_trip(self):
       
        if self.status in ['completed']:
            raise ValueError("Cannot cancel completed trip")
        
        self.status = 'canceled'
        self.trip_canceled = True
        self.save()

    def get_duration(self):
        """Get trip duration in hours"""
        if self.start_time and self.end_time:
            duration = self.end_time - self.start_time
            return duration.total_seconds() / 3600
        return None

    def get_status_display_color(self):
        """Get color for status display"""
        status_colors = {
            'waiting': '#FFA500',    # Orange
            'started': '#00BFFF',    # Blue
            'ontrip': '#32CD32',     # Green
            'completed': '#228B22',  # Dark Green
            'canceled': '#DC143C',   # Red
        }
        return status_colors.get(self.status, '#808080')

    def __str__(self):
        return f"Trip #{self.pk} - {self.renter.user.username} - {self.get_status_display()}"

    class Meta:
        ordering = ['-trip_date']
        indexes = [
            models.Index(fields=['status', 'trip_date']),
            models.Index(fields=['renter', 'status']),
            models.Index(fields=['bike_owner', 'status']),
            models.Index(fields=['bike', 'status']),
        ]
