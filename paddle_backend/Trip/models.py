from django.db import models
from django.contrib.auth.models import User
from Rider.models import UserProfile
from Owner.models import OwnerProfile
from Bikes.models import Bikes
from decimal import Decimal
import pyotp
from datetime import datetime

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

    COMMISSION_RATE = Decimal('0.15')  # 15% platform commission

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
    
    # Unlock code fields
    unlock_code = models.CharField(max_length=6, blank=True)
    code_generated_at = models.DateTimeField(null=True)

    def process_unlock_status(self, is_unlocked):
        chat_room = ChatRoom.objects.get(trip=self)
        if is_unlocked:
            Message.objects.create(
                chat_room=chat_room,
                content="🔓 Bike has been unlocked successfully!"
            )
        else:
            Message.objects.create(
                chat_room=chat_room,
                content="🔒 Bike has been locked"
            )

    
    def calculate_commission(self):
    
        self.commission_amount = self.price * self.COMMISSION_RATE
        self.owner_payout = self.price - self.commission_amount
        self.save()

    def process_payment(self):
        
        try:
            self.payment_status = 'processing'
            self.calculate_commission()
            self.payment_status = 'completed'
            self.payment_processed_at = datetime.now()
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
        self.end_time = datetime.now()
        self.process_payment()
        self.save()

    def __str__(self):
        return f"Trip #{self.pk} from ({self.origin_latitude}, {self.origin_longitude}) to ({self.destination_latitude}, {self.destination_longitude})"

    class Meta:
        ordering = ['-trip_date']
