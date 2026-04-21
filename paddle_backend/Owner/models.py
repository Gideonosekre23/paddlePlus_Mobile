from django.db import models
from django.contrib.auth.models import User
from django.core.validators import MinLengthValidator, MaxLengthValidator

class OwnerProfile(models.Model):
    VERIFICATION_STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('verified', 'Verified'),
        ('rejected', 'Rejected')
    ]

    user = models.OneToOneField(User, related_name='owner_profile', on_delete=models.CASCADE)
    profile_picture = models.ImageField(upload_to="owner/profile/")
    cpn = models.CharField(max_length=13, validators=[MinLengthValidator(13), MaxLengthValidator(13)])
    phone_number = models.CharField(max_length=15)
    created_on = models.DateTimeField(auto_now_add=True)
    edited_at = models.DateTimeField(auto_now=True)
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    verification_status = models.CharField(
        max_length=20,
        choices=VERIFICATION_STATUS_CHOICES,
        default='pending'
    )
    verification_session_id = models.CharField(max_length=100, blank=True)

    def __str__(self):
        return f"{self.user.username}'s Profile"

    def get_location(self):
        return {
            'latitude': self.latitude,
            'longitude': self.longitude
        }

    def update_verification_status(self, status):
        self.verification_status = status
        self.save()
