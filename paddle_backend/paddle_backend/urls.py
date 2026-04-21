from django.contrib import admin
from django.urls import include, path
from django.conf import settings
from django.conf.urls.static import static

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
    path('bikes/nearby/', bikes_views.get_nearby_bikes, name='nearby-bikes'),
    path('bikes/hardware/gps/', bikes_views.receive_hardware_gps, name='hardware_gps'),
    path('bikes/<int:bike_id>/', bikes_views.get_bike, name='get-bike'),
    path('bikes/<int:bike_id>/edit/', bikes_views.edit_bike, name='edit-bike'),
    path('bikes/<int:bike_id>/activate/', bikes_views.activate_bike, name='activate-bike'),
    path('bikes/<int:bike_id>/unlock/', bikes_views.get_bike_unlock_code, name='unlock-bike'),
    path('bikes/<int:bike_id>/lock/', bikes_views.lock_bike, name='lock-bike'),
    path('bikes/<int:bike_id>/toggle/', bikes_views.toggle_bike_availability, name='toggle-bike'),
    path('bikes/<int:bike_id>/remove/', bikes_views.remove_bike, name='remove_bike'),


    # Owner endpoints
    path('owner/dashboard/', owner_views.owner_dashboard, name='owner-dashboard'),
    path('owner/profile/', owner_views.get_Owner_profile, name='owner-profile'),
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
    path('rider/profile/', rider_views.get_Rider_profile, name='rider-profile'),
    path('rider/register/', rider_views.register_Rider, name='rider-register'),
    path('rider/login/', rider_views.Login_Rider, name='rider-login'),
    path('rider/logout/', rider_views.Logout_Rider, name='rider-logout'),
    path('rider/profile/update/', rider_views.update_Rider_profile, name='update-rider-profile'),
    path('rider/profile/delete/', rider_views.delete_Rider_profile, name='delete-rider-profile'),
    path('rider/search/<str:username>/', rider_views.search_Rider_profile, name='search-rider'),
    path('rider/location/update/', rider_views.update_location, name='update-rider-location'),
    path('rider/token/check/', rider_views.check_token_validity, name='check-token'),
    path('rider/payment/setup/', rider_views.setup_payment, name='rider-payment-setup'),
    path('rider/webhook/stripe/', rider_views.stripe_webhook, name='rider-stripe-webhook'),
    path('rider/webhook/stripe/setup/', rider_views.stripe_setup_webhook, name='rider-stripe-setup-webhook'),

    # RideRequest endpoints
    path('riderequest/request/', riderequest_views.request_ride, name='request-ride'),
    path('riderequest/request-with-payment/', riderequest_views.request_ride_with_payment, name='request-ride-with-payment'),
    path('riderequest/estimate-price/', riderequest_views.estimate_price, name='estimate_price'),
    path('riderequest/owner/pending/', riderequest_views.get_owner_pending_requests, name='owner-pending-requests'),
    path('riderequest/status/<str:temp_request_id>/', riderequest_views.get_request_status, name='request-status'),
    path('riderequest/accept/<str:temp_request_id>/', riderequest_views.accept_ride_request, name='accept_ride_request'),
    path('riderequest/decline/<str:temp_request_id>/', riderequest_views.decline_ride_request, name='decline-ride'),
    path('riderequest/cancel-request/<str:temp_request_id>/', riderequest_views.cancel_ride_request, name='cancel_ride_request'),
    # Trip endpoints
    path('trip/active/', trip_views.get_active_trip, name='active-trip'),
    path('trip/start/<int:trip_id>/', trip_views.start_trip, name='start-trip'),
    path('trip/begin/<int:trip_id>/', trip_views.begin_trip, name='begin-trip'),
    path('trip/end/<int:trip_id>/', trip_views.end_trip, name='end-trip'),
    path('trip/cancel/<int:trip_id>/', trip_views.cancel_trip, name='cancel-trip'),
    path('trip/<int:trip_id>/rate/', trip_views.rate_trip, name='rate-trip'),
    path('trip/<int:trip_id>/rate-rider/', trip_views.rate_rider, name='rate-rider'),
    path('trip/user/trips/', trip_views.get_user_trips, name='get-user-trips'),
    path('trip/owner/trips/', trip_views.get_owner_trips, name='get-owner-trips'),

    # Chat endpoints
    path('chat/room/<int:trip_id>/', chat_views.get_chat_room, name='get-chat-room'),
    path('chat/send/<int:chat_room_id>/', chat_views.send_message, name='send-message'),
    path('chat/read/<int:chat_room_id>/', chat_views.mark_messages_read, name='mark-messages-read'),


     # Allauth social login URLs
    path('accounts/', include('allauth.urls')),

     
]

  

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)