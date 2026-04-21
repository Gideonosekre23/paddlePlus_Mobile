from django.db import models
from django.contrib.auth.models import User
from django.core.validators import MinLengthValidator, MaxLengthValidator
from django.core.exceptions import ValidationError

def validate_image_size(image):
    max_mb = 5
    if image.size > max_mb * 1024 * 1024:
        raise ValidationError(f'Image file size must be under {max_mb}MB.')

class OwnerProfile(models.Model):
    VERIFICATION_STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('verified', 'Verified'),
        ('rejected', 'Rejected')
    ]

    user = models.OneToOneField(User, related_name='owner_profile', on_delete=models.CASCADE)
    profile_picture = models.ImageField(upload_to="profile_pics/", null=True, blank=True, validators=[validate_image_size])
    cpn = models.CharField(max_length=13, validators=[MinLengthValidator(13), MaxLengthValidator(13)])
    phone_number = models.CharField(max_length=15)
    address = models.CharField(max_length=255, null=True, blank=True)
    total_earnings = models.DecimalField(
        max_digits=10, 
        decimal_places=2, 
        default=0.00,
        help_text="Total earnings from all bikes own")
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
    apple_sub = models.CharField(max_length=100, null=True, blank=True, unique=True)
    stripe_customer_id = models.CharField(max_length=255, null=True, blank=True)

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
