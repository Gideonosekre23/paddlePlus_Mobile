from django.db import models
from django.contrib.auth.models import User
from Owner.models import OwnerProfile
from Rider.models import UserProfile

class Ride_Request(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('declined', 'Declined'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled')
    ]
    
    PAYMENT_STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('completed', 'Completed'),
        ('failed', 'Failed'),
        ('refunded', 'Refunded')
    ]
    
    Rider = models.ForeignKey(UserProfile, related_name='ride_requests', on_delete=models.CASCADE)
    Owner = models.ForeignKey(OwnerProfile, related_name='ride_requests', on_delete=models.SET_NULL, null=True, blank=True)
    bike = models.ForeignKey('Bikes.Bikes', on_delete=models.SET_NULL, null=True, related_name='ride_requests')
    payment_type = models.CharField(max_length=50, default='card')
    pickup_latitude = models.FloatField(default=0.0)
    pickup_longitude = models.FloatField(default=0.0)
    destination_latitude = models.FloatField(default=0.0)
    destination_longitude = models.FloatField(default=0.0)
    requested_time = models.DateTimeField(default=None, null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    is_accepted = models.BooleanField(default=False)
    price = models.DecimalField(max_digits=10, decimal_places=2)  
    distance = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    duration = models.DurationField(null=True, blank=True)
    destination_address = models.CharField(max_length=255, null=True, blank=True)
    origin_address = models.CharField(max_length=255, null=True, blank=True)
    stripe_customer_id = models.CharField(max_length=255, blank=True, null=True)
    default_payment_method = models.CharField(max_length=255, blank=True, null=True)
    total_amount = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)  
    platform_commission = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True) 
    owner_earnings = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)  
    payment_status = models.CharField(max_length=20, choices=PAYMENT_STATUS_CHOICES, default='pending')
    payment_intent_id = models.CharField(max_length=255, null=True, blank=True)  
    payment_processed_at = models.DateTimeField(null=True, blank=True)

    def save(self, *args, **kwargs):
        if self.price and not self.total_amount:
            from Trip.models import Trip
            self.total_amount = self.price
            self.platform_commission = self.price * float(Trip.COMMISSION_RATE)
            self.owner_earnings = self.price - self.platform_commission
        super().save(*args, **kwargs)

    def __str__(self):
        return f"Request by {self.Rider.user.username} from ({self.pickup_latitude}, {self.pickup_longitude}) to ({self.destination_latitude}, {self.destination_longitude})"

    class Meta:
        ordering = ['-requested_time']
        indexes = [
            models.Index(fields=['status', 'requested_time']),
            models.Index(fields=['Rider', 'status']),
            models.Index(fields=['Owner', 'status']),
            models.Index(fields=['payment_status']),
            
            models.Index(fields=['Rider', 'bike', 'status']),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=['Rider', 'bike'],
                condition=models.Q(status__in=['pending', 'accepted']),
                name='unique_pending_request_per_rider_bike'
            ),
           
            models.UniqueConstraint(
                fields=['Rider'],
                condition=models.Q(status='pending'),
                name='unique_pending_request_per_rider'
            )
        ]
