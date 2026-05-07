import uuid
from django.db import models
from django.contrib.auth.models import User
from Owner.models import OwnerProfile
from Rider.models import UserProfile


class Ride_Request(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('declined', 'Declined'),
        ('cancelled', 'Cancelled'),
    ]

    Rider = models.ForeignKey(UserProfile, related_name='ride_requests', on_delete=models.CASCADE)
    Owner = models.ForeignKey(OwnerProfile, related_name='ride_requests', on_delete=models.SET_NULL, null=True, blank=True)
    bike = models.ForeignKey('Bikes.Bikes', on_delete=models.SET_NULL, null=True, blank=True)
    pickup_latitude = models.FloatField(default=0.0)
    pickup_longitude = models.FloatField(default=0.0)
    destination_latitude = models.FloatField(default=0.0)
    destination_longitude = models.FloatField(default=0.0)
    requested_time = models.DateTimeField(auto_now_add=True)
    is_accepted = models.BooleanField(default=False)
    price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    distance = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    payment_type = models.CharField(max_length=50, default='card', blank=True)
    payment_intent_id = models.CharField(max_length=200, blank=True)
    temp_request_id = models.UUIDField(default=uuid.uuid4, unique=True)
    origin_address = models.CharField(max_length=500, blank=True, default='')
    destination_address = models.CharField(max_length=500, blank=True, default='')

    def __str__(self):
        return f"Request {self.temp_request_id} — {self.status}"
