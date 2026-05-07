from django.contrib import admin
from django.urls import path
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

    # Hardware GPS push (unauthenticated — called by Arduino over SIM800L)
    path('gps/', bikes_views.hardware_gps_update, name='hardware-gps'),

    # Bikes endpoints
    path('bikes/add/', bikes_views.add_bike, name='add-bike'),
    path('bikes/owner/', bikes_views.get_owner_bikes, name='owner-bikes'),
    path('bikes/remove/<int:bike_id>/', bikes_views.remove_bike, name='remove-bike'),
    path('bikes/activate/<int:bike_id>/', bikes_views.activate_bike, name='activate-bike'),
    path('bikes/unlock/<int:bike_id>/', bikes_views.get_bike_unlock_code, name='unlock-bike'),
    path('bikes/lock/<int:bike_id>/', bikes_views.lock_bike, name='lock-bike'),
    path('bikes/toggle/<int:bike_id>/', bikes_views.toggle_bike_availability, name='toggle-bike'),
    path('bikes/nearby/', bikes_views.get_nearby_bikes, name='nearby-bikes'),

    # Owner endpoints
    path('owner/check-token/', owner_views.check_token_validity, name='owner-check-token'),
    path('owner/password/forgot/', owner_views.forgot_password, name='owner-forgot-password'),
    path('owner/password/verify-otp/', owner_views.verify_reset_otp, name='owner-verify-otp'),
    path('owner/password/reset/', owner_views.reset_password, name='owner-reset-password'),
    path('owner/password/change/', owner_views.change_password, name='owner-change-password'),
    path('owner/register/', owner_views.register_Owner, name='owner-register'),
    path('owner/login/', owner_views.Login_Owner, name='owner-login'),
    path('owner/logout/', owner_views.Logout_Owner, name='owner-logout'),
    path('owner/profile/', owner_views.get_owner_profile, name='owner-profile'),
    path('owner/profile/update/', owner_views.update_Owner_profile, name='update-owner-profile'),
    path('owner/profile/delete/', owner_views.delete_Owner_profile, name='delete-owner-profile'),
    path('owner/webhook/stripe/', owner_views.stripe_webhook, name='owner-stripe-webhook'),
    path('owner/payment/connect/', owner_views.connect_stripe_account, name='owner-connect'),
    path('owner/payment/connect/status/', owner_views.connect_stripe_status, name='owner-connect-status'),
    path('owner/wallet/', owner_views.request_withdrawal, name='owner-wallet'),
    path('owner/wallet/history/', owner_views.payout_history, name='owner-payout-history'),

    # Rider endpoints
    path('rider/register/', rider_views.register_Rider, name='rider-register'),
    path('rider/login/', rider_views.Login_Rider, name='rider-login'),
    path('rider/logout/', rider_views.Logout_Rider, name='rider-logout'),
    path('rider/profile/', rider_views.get_rider_profile, name='rider-profile'),
    path('rider/profile/update/', rider_views.update_Rider_profile, name='update-rider-profile'),
    path('rider/profile/delete/', rider_views.delete_Rider_profile, name='delete-rider-profile'),
    path('rider/location/update/', rider_views.update_location, name='update-rider-location'),
    path('rider/token/check/', rider_views.check_token_validity, name='check-token'),
    path('rider/webhook/stripe/', rider_views.stripe_webhook, name='rider-stripe-webhook'),
    path('rider/payment/setup/', rider_views.setup_payment_method, name='rider-payment-setup'),
    path('rider/payment/confirm/', rider_views.confirm_payment_method, name='rider-payment-confirm'),
    path('rider/password/forgot/', rider_views.forgot_password, name='rider-forgot-password'),
    path('rider/password/verify-otp/', rider_views.verify_reset_otp, name='rider-verify-otp'),
    path('rider/password/reset/', rider_views.reset_password, name='rider-reset-password'),
    path('rider/password/change/', rider_views.change_password, name='rider-change-password'),
    path('rider/payment/methods/', rider_views.list_payment_methods, name='rider-payment-methods'),
    path('rider/payment/method/<str:pm_id>/delete/', rider_views.delete_payment_method, name='rider-delete-payment-method'),

    # RideRequest endpoints
    path('riderequest/estimate-price/', riderequest_views.estimate_price, name='estimate-price'),
    path('riderequest/request-with-payment/', riderequest_views.request_ride_with_payment, name='request-ride-with-payment'),
    path('riderequest/request/', riderequest_views.request_ride, name='request-ride'),
    path('riderequest/pending/', riderequest_views.get_owner_pending_requests, name='owner-pending-requests'),
    path('riderequest/status/<str:temp_request_id>/', riderequest_views.get_request_status, name='request-status'),
    path('riderequest/cancel-request/<str:temp_request_id>/', riderequest_views.cancel_ride_request_by_temp_id, name='cancel-request'),
    path('riderequest/accept/<str:temp_request_id>/', riderequest_views.accept_ride_request, name='accept-ride'),
    path('riderequest/decline/<str:temp_request_id>/', riderequest_views.decline_ride_request, name='decline-ride'),

    # Trip endpoints — owner-specific routes must come before the generic <trip_id> pattern
    path('trip/active/', trip_views.get_active_trip, name='active-trip'),
    path('trip/user/trips/', trip_views.get_user_trips, name='user-trips'),
    path('trip/owner/trips/', trip_views.get_owner_trips, name='owner-trips'),
    path('trip/owner/earnings/', trip_views.get_owner_earnings, name='owner-earnings'),
    path('trip/owner/<int:trip_id>/', trip_views.get_owner_trip_detail, name='owner-trip-detail'),
    path('trip/start/<int:trip_id>/', trip_views.start_trip, name='start-trip'),
    path('trip/begin/<int:trip_id>/', trip_views.begin_trip, name='begin-trip'),
    path('trip/end/<int:trip_id>/', trip_views.end_trip, name='end-trip'),
    path('trip/cancel/<int:trip_id>/', trip_views.cancel_trip, name='cancel-trip'),
    path('trip/<int:trip_id>/', trip_views.get_rider_trip_detail, name='rider-trip-detail'),
    path('trip/<int:trip_id>/rate/', trip_views.rate_trip, name='rate-trip'),
    path('trip/<int:trip_id>/report/', trip_views.report_trip, name='report-trip'),

    # Chat endpoints
    path('chat/room/<int:trip_id>/', chat_views.get_chat_room, name='get-chat-room'),
    path('chat/read/<int:chat_room_id>/', chat_views.mark_messages_read, name='mark-messages-read'),

    # Notification history
    path('notifications/', chat_views.get_notification_history, name='notification-history'),
    path('notifications/mark-read/', chat_views.mark_notifications_read, name='mark-notifications-read'),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
