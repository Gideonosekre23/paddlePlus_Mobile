from django.db import models
from django.contrib.auth.models import User
from django.conf import settings
from Rider.models import UserProfile
from Owner.models import OwnerProfile
from Bikes.models import Bikes
from decimal import Decimal
import pyotp
from django.utils import timezone

class Trip(models.Model):
    STATUS_CHOICES = [
        ('created', 'Created'),
        ('waiting', 'Waiting'),
        ('started', 'Started'),
        ('canceled', 'Canceled'),
        ('ontrip', 'On Trip'),
        ('completed', 'Completed'),
    ]

    PAYMENT_STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('processing', 'Processing'),
        ('completed', 'Completed'),
        ('failed', 'Failed')
    ]

    @property
    def COMMISSION_RATE(self):
        return Decimal(str(getattr(settings, 'PLATFORM_COMMISSION_RATE', '0.15')))

    renter = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='trips_taken')
    bike_owner = models.ForeignKey(OwnerProfile, on_delete=models.CASCADE, related_name='trips_given')
    bike = models.ForeignKey(Bikes, on_delete=models.CASCADE)
    trip_date = models.DateTimeField(auto_now_add=True)
    start_time = models.DateTimeField(null=True, blank=True)
    end_time = models.DateTimeField(null=True, blank=True)
    origin_latitude = models.FloatField(null=True, blank=True)
    origin_longitude = models.FloatField(null=True, blank=True)
    destination_latitude = models.FloatField(null=True, blank=True)
    destination_longitude = models.FloatField(null=True, blank=True)
    origin_map = models.ImageField(upload_to='trip_maps/', null=True, blank=True)
    destination_map = models.ImageField(upload_to='trip_maps/', null=True, blank=True)
    distance = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    payment_type = models.CharField(max_length=100)
    trip_canceled = models.BooleanField(default=False)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='created')
    
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
    
    # Payment intent tracking for two-stage payment
    payment_intent_id = models.CharField(max_length=100, blank=True, default='')

    # Address fields (populated from Ride_Request on trip creation)
    origin_address = models.CharField(max_length=255, null=True, blank=True)
    destination_address = models.CharField(max_length=255, null=True, blank=True)

    # Stripe transfer record
    stripe_transfer_id = models.CharField(max_length=255, null=True, blank=True)

    # Rider rating and review (set when rider rates the trip)
    rider_rating = models.PositiveSmallIntegerField(null=True, blank=True)
    rider_review = models.TextField(null=True, blank=True)

    # Owner rating and review
    owner_rating = models.PositiveSmallIntegerField(null=True, blank=True)
    owner_review = models.TextField(null=True, blank=True)

    # Rating guard — prevents a rider from rating the same trip twice
    is_rated = models.BooleanField(default=False)

    # Unlock code fields
    unlock_code = models.CharField(max_length=6, blank=True)
    code_generated_at = models.DateTimeField(null=True)

    def process_unlock_status(self, is_unlocked, sender=None):
        from chat.models import ChatRoom, Message
        try:
            chat_room = ChatRoom.objects.get(trip=self)
        except ChatRoom.DoesNotExist:
            return
        message_sender = sender or self.bike_owner.user
        content = "🔓 Bike has been unlocked successfully!" if is_unlocked else "🔒 Bike has been locked"
        Message.objects.create(chat_room=chat_room, sender=message_sender, content=content)

    
    def calculate_commission(self):
        if self.price is None:
            return
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

    def complete_trip(self):
       
        if self.status != 'ontrip':
            raise ValueError("Trip must be 'ontrip' to complete")
        
        self.status = 'completed'
        self.end_time = timezone.now()
        self.process_payment()
        self.save()

    def __str__(self):
        return f"Trip #{self.pk} from ({self.origin_latitude}, {self.origin_longitude}) to ({self.destination_latitude}, {self.destination_longitude})"

    class Meta:
        ordering = ['-trip_date']
