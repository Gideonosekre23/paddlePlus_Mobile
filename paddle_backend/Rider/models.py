from django.db import models
from django.contrib.auth.models import User
from django.core.validators import MinLengthValidator, MaxLengthValidator
from django.core.exceptions import ValidationError

def validate_image_size(image):
    max_mb = 5
    if image.size > max_mb * 1024 * 1024:
        raise ValidationError(f'Image file size must be under {max_mb}MB.')

class UserProfile(models.Model):
    VERIFICATION_STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('verified', 'Verified'),
        ('rejected', 'Rejected')
    ]

    user = models.OneToOneField(User, on_delete=models.CASCADE)
    cpn = models.CharField(max_length=13, validators=[MinLengthValidator(13), MaxLengthValidator(13)])
    phone_number = models.CharField(max_length=15)
    address = models.CharField(max_length=255, null=True, blank=True)
    profile_picture = models.ImageField(upload_to='profile_pictures/', null=True, blank=True, validators=[validate_image_size])
    age = models.PositiveIntegerField(blank=True, null=True)
    is_subscribed_to_newsletter = models.BooleanField(default=False)
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
    default_payment_method = models.CharField(max_length=255, null=True, blank=True)
    rider_rating = models.DecimalField(max_digits=3, decimal_places=2, default=5.0)
    rider_rating_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user.username}'s Profile"
