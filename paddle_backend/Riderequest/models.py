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

    Rider = models.ForeignKey(UserProfile, related_name='ride_requests', on_delete=models.CASCADE)
    Owner = models.ForeignKey(OwnerProfile, related_name='ride_requests', on_delete=models.SET_NULL, null=True, blank=True)
    bike = models.ForeignKey('Bikes.Bikes', on_delete=models.SET_NULL, null=True, related_name='ride_requests')
    payment_type = models.CharField(max_length=50, default='card')
    pickup_latitude = models.FloatField(default=0.0)
    pickup_longitude = models.FloatField(default=0.0)
    destination_latitude = models.FloatField(default=0.0)
    destination_longitude = models.FloatField(default=0.0)
    requested_time = models.DateTimeField(auto_now_add=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    is_accepted = models.BooleanField(default=False)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    distance = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    duration = models.DurationField(null=True, blank=True)

    def __str__(self):
        return f"Request by {self.Rider.user.username} from ({self.pickup_latitude}, {self.pickup_longitude}) to ({self.destination_latitude}, {self.destination_longitude})"

    class Meta:
        ordering = ['-requested_time']
        indexes = [
            models.Index(fields=['status', 'requested_time']),
            models.Index(fields=['Rider', 'status']),
            models.Index(fields=['Owner', 'status'])
        ]
