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
    profile_picture = models.ImageField(upload_to="owner/profile/", null=True, blank=True)
    cpn = models.CharField(max_length=13, validators=[MinLengthValidator(13), MaxLengthValidator(13)])
    phone_number = models.CharField(max_length=15)
    address = models.CharField(max_length=255, blank=True, default='')
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
    stripe_account_id = models.CharField(max_length=255, null=True, blank=True)
    apple_sub = models.CharField(max_length=255, null=True, blank=True, unique=True)

    def __str__(self):
        return f"{self.user.username}'s Profile"

    def get_location(self):
        return {
            'latitude': self.latitude,
            'longitude': self.longitude
        }

    pending_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    def update_verification_status(self, status):
        self.verification_status = status
        self.save()


class PayoutRecord(models.Model):
    PAYOUT_METHOD_CHOICES = [('instant', 'Instant'), ('standard', 'Standard')]
    STATUS_CHOICES = [('pending', 'Pending'), ('paid', 'Paid'), ('failed', 'Failed')]

    owner = models.ForeignKey(OwnerProfile, on_delete=models.CASCADE, related_name='payouts')
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    stripe_transfer_id = models.CharField(max_length=100)
    stripe_payout_id = models.CharField(max_length=100, blank=True)
    method = models.CharField(max_length=20, choices=PAYOUT_METHOD_CHOICES, default='instant')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Payout #{self.pk} — {self.owner.user.username} — ${self.amount}"
