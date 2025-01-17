from django.contrib import admin
from django.urls import path
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
    TokenVerifyView
)
from Bikes import views as bikes_views
from Owner import views as owner_views
from Rider import views as rider_views
from Riderequest import views as riderequest_views
from Trip import views as trip_views
from chat import views as chat_views

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/token/verify/', TokenVerifyView.as_view(), name='token_verify'),

    # Bikes endpoints
    path('bikes/add/', bikes_views.add_bike, name='add-bike'),
    path('bikes/owner/', bikes_views.get_driver_bikes, name='get-driver-bikes'),
    path('bikes/activate/<int:bike_id>/', bikes_views.activate_bike, name='activate-bike'),
    path('bikes/unlock/<int:bike_id>/', bikes_views.get_bike_unlock_code, name='unlock-bike'),
    path('bikes/lock/<int:bike_id>/', bikes_views.lock_bike, name='lock-bike'),
    path('bikes/toggle/<int:bike_id>/', bikes_views.toggle_bike_availability, name='toggle-bike'),
    path('bikes/nearby/', bikes_views.get_nearby_bikes, name='nearby-bikes'),
   path('bikes/<int:bike_id>/remove/', bikes_views.remove_bike, name='remove_bike'),


    # Owner endpoints
    path('owner/list/', owner_views.customer_list, name='owner-list'),
    path('owner/register/', owner_views.register_Owner, name='owner-register'),
    path('owner/login/', owner_views.Login_Owner, name='owner-login'),
    path('owner/logout/', owner_views.Logout_Owner, name='owner-logout'),
    path('owner/profile/update/', owner_views.update_Owner_profile, name='update-owner-profile'),
    path('owner/profile/delete/', owner_views.delete_Owner_profile, name='delete-owner-profile'),
    path('owner/search/<str:username>/', owner_views.search_Owner_profile, name='search-owner'),
    path('owner/webhook/stripe/', owner_views.stripe_webhook, name='owner-stripe-webhook'),

    # Rider endpoints
    path('rider/list/', rider_views.Rider_list, name='rider-list'),
    path('rider/register/', rider_views.register_Rider, name='rider-register'),
    path('rider/login/', rider_views.Login_Rider, name='rider-login'),
    path('rider/logout/', rider_views.Logout_Rider, name='rider-logout'),
    path('rider/profile/update/', rider_views.update_Rider_profile, name='update-rider-profile'),
    path('rider/profile/delete/', rider_views.delete_Rider_profile, name='delete-rider-profile'),
    path('rider/search/<str:username>/', rider_views.search_Rider_profile, name='search-rider'),
    path('rider/location/update/', rider_views.update_location, name='update-rider-location'),
    path('rider/token/check/', rider_views.check_token_validity, name='check-token'),
    path('rider/webhook/stripe/', rider_views.stripe_webhook, name='rider-stripe-webhook'),

    # RideRequest endpoints
    path('riderequest/request/', riderequest_views.request_ride, name='request-ride'),
    path('riderequest/accept/<int:request_id>/', riderequest_views.accept_ride_request, name='accept-ride'),
    path('riderequest/decline/<int:request_id>/', riderequest_views.decline_ride_request, name='decline-ride'),

    # Trip endpoints
    path('trip/start/<int:trip_id>/', trip_views.start_trip, name='start-trip'),
    path('trip/end/<int:trip_id>/', trip_views.end_trip, name='end-trip'),
    path('trip/cancel/<int:trip_id>/', trip_views.cancel_trip, name='cancel-trip'),

    # Chat endpoints
    path('chat/room/<int:trip_id>/', chat_views.get_chat_room, name='get-chat-room'),
    path('chat/send/<int:chat_room_id>/', chat_views.send_message, name='send-message'),
    path('chat/read/<int:chat_room_id>/', chat_views.mark_messages_read, name='mark-messages-read'),
]
