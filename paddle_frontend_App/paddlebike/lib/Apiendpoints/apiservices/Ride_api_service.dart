import '../models/api_response.dart';
import '../models/Ride_models.dart';
import 'base_api_service.dart';

class OwnerTripsApiService {
  static const String _tripBasePath = '/trip';

  /// Get owner trips from the backend
  /// Corresponds to GET /trip/owner/trips/
  static Future<ApiResponse<OwnerTripsResponse>> getOwnerTrips() {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.get<OwnerTripsResponse>(
        '$_tripBasePath/owner/trips/',
        fromJson: OwnerTripsResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Get owner trips with filtering
  /// Corresponds to GET /trip/owner/trips/?status=completed&date_from=2024-01-01
  static Future<ApiResponse<OwnerTripsResponse>> getOwnerTripsFiltered({
    String? status,
    String? dateFrom,
    String? dateTo,
  }) {
    final Map<String, String> params = {};

    if (status != null) params['status'] = status;
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;

    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.get<OwnerTripsResponse>(
        '$_tripBasePath/owner/trips/',
        params: params,
        fromJson: OwnerTripsResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Get single trip details
  /// Corresponds to GET /trip/owner/{trip_id}/
  static Future<ApiResponse<OwnerTrip>> getOwnerTripDetails(String tripId) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.get<OwnerTrip>(
        '$_tripBasePath/owner/$tripId/',
        fromJson: OwnerTrip.fromJson,
        auth: true,
      );
    });
  }

  /// Accept or reject a ride request (if you have this feature)
  /// Corresponds to POST /trip/owner/respond/{trip_id}/
  static Future<ApiResponse<Map<String, dynamic>>> respondToRideRequest(
    String tripId,
    bool accept,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '$_tripBasePath/owner/respond/$tripId/',
        body: {'accept': accept},
        fromJson: (json) => json,
        auth: true,
      );
    });
  }

  /// Cancel an owner trip
  /// Corresponds to POST /trip/owner/cancel/{trip_id}/
  static Future<ApiResponse<Map<String, dynamic>>> cancelOwnerTrip(
    String tripId,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '$_tripBasePath/owner/cancel/$tripId/',
        fromJson: (json) => json,
        auth: true,
      );
    });
  }

  /// Get owner earnings summary
  /// Corresponds to GET /trip/owner/earnings/
  static Future<ApiResponse<Map<String, dynamic>>> getOwnerEarnings({
    String? period, // 'daily', 'weekly', 'monthly'
  }) {
    final Map<String, String> params = {};
    if (period != null) params['period'] = period;

    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.get<Map<String, dynamic>>(
        '$_tripBasePath/owner/earnings/',
        params: params,
        fromJson: (json) => json,
        auth: true,
      );
    });
  }
}
