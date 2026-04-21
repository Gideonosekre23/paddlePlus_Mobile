import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'paddle_backend.settings')
django.setup()

from django.contrib.auth.models import User
from Rider.models import UserProfile
from Owner.models import OwnerProfile

def export_login_info():
    print("📝 Exporting login information...")
    
    # Get all riders and owners
    riders = UserProfile.objects.select_related('user').all()
    owners = OwnerProfile.objects.select_related('user').all()
    
    # Create login info content
    content = []
    content.append("=" * 60)
    content.append("🚴 PADDLE PLUS - LOGIN CREDENTIALS")
    content.append("=" * 60)
    content.append("")
    
    # RIDERS SECTION
    content.append("👥 RIDERS (UserProfile)")
    content.append("-" * 40)
    content.append("Username | Email | Password | Phone | Status")
    content.append("-" * 40)
    
    for rider in riders:
        user = rider.user
        content.append(f"{user.username:<12} | {user.email:<20} | password123 | {rider.phone_number:<15} | {rider.verification_status}")
    
    content.append("")
    
    # OWNERS SECTION  
    content.append("🏠 OWNERS (OwnerProfile)")
    content.append("-" * 40)
    content.append("Username | Email | Password | Phone | Status | Bikes | Earnings")
    content.append("-" * 40)
    
    for owner in owners:
        user = owner.user
        bike_count = owner.bikes_owned.count()
        earnings = owner.total_earnings
        content.append(f"{user.username:<12} | {user.email:<20} | password123 | {owner.phone_number:<15} | {owner.verification_status:<8} | {bike_count:<5} | {earnings} RON")
    
    content.append("")
    content.append("=" * 60)
    content.append("📱 MOBILE APP LOGIN")
    content.append("=" * 60)
    content.append("")
    content.append("🚴 RIDER APP:")
    for rider in riders:
        content.append(f"  Email: {rider.user.email}")
        content.append(f"  Password: password123")
        content.append(f"  Phone: {rider.phone_number}")
        content.append("")
    
    content.append("🏠 OWNER APP:")
    for owner in owners:
        content.append(f"  Email: {owner.user.email}")
        content.append(f"  Password: password123")
        content.append(f"  Phone: {owner.phone_number}")
        content.append(f"  Bikes: {owner.bikes_owned.count()}")
        content.append("")
    
    content.append("=" * 60)
    content.append("🔧 API TESTING")
    content.append("=" * 60)
    content.append("")
    content.append("POST /rider/login/")
    content.append('{"username": "rider1", "password": "password123"}')
    content.append("")
    content.append("POST /owner/login/")
    content.append('{"username": "owner1", "password": "password123"}')
    content.append("")
    
    # Write to file
    with open('login_credentials.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(content))
    
    print("✅ Login info exported to: login_credentials.txt")
    print(f"📊 Total Riders: {riders.count()}")
    print(f"📊 Total Owners: {owners.count()}")
    
    # Also print summary to console
    print("\n" + "=" * 50)
    print("📱 QUICK LOGIN REFERENCE:")
    print("=" * 50)
    print("\n🚴 RIDERS:")
    for rider in riders:
        print(f"  {rider.user.username} | {rider.user.email} | password123")
    
    print("\n🏠 OWNERS:")
    for owner in owners:
        bike_count = owner.bikes_owned.count()
        print(f"  {owner.user.username} | {owner.user.email} | password123 | {bike_count} bikes")

if __name__ == "__main__":
    export_login_info()
