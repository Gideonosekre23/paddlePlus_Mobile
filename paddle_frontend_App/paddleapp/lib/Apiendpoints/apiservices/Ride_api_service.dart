import '../models/api_response.dart';
import '../models/Ride_models.dart';
import 'base_api_service.dart';

class RideApiService {
  static const String _rideRequestBasePath = '/riderequest';
  static const String _tripBasePath = '/trip';
  static const String _bikesBasePath = '/bikes';

  /// Estimate the price for a ride.
  /// Corresponds to POST /riderequest/estimate-price/
  static Future<ApiResponse<EstimatePriceResponse>> estimatePrice(
    EstimatePriceRequest request,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<EstimatePriceResponse>(
        '$_rideRequestBasePath/estimate-price/',
        body: request.toJson(),
        fromJson: EstimatePriceResponse.fromJson,
        auth:
            true, // Assuming price estimation requires user context for preferences or history
      );
    });
  }

  /// Request a new ride. Handles both success and bike-conflict (preferred bike taken) responses.
  /// Corresponds to POST /riderequest/request/
  static Future<ApiResponse<RideRequestResponse>> requestRide(
    RideRequestRequest request,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<RideRequestResponse>(
        '$_rideRequestBasePath/request/',
        body: request.toJson(),
        fromJson: RideRequestResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Start an existing trip.
  /// Corresponds to POST /trip/start/{trip_id}/
  static Future<ApiResponse<StartTripResponse>> startTrip(String tripId) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<StartTripResponse>(
        '$_tripBasePath/start/$tripId/',
        fromJson: StartTripResponse.fromJson,
        auth: true,
      );
    });
  }

  /// End an ongoing trip.
  /// Corresponds to POST /trip/end/{trip_id}/
  static Future<ApiResponse<EndTripResponse>> endTrip(String tripId) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<EndTripResponse>(
        '$_tripBasePath/end/$tripId/',
        fromJson: EndTripResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Cancel a trip.
  /// Corresponds to POST /trip/cancel/{trip_id}/
  static Future<ApiResponse<CancelTripResponse>> cancelTrip(String tripId) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<CancelTripResponse>(
        '$_tripBasePath/cancel/$tripId/',
        fromJson: CancelTripResponse.fromJson,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<CancelRideRequestResponse>> cancelRideRequest(
    String tempRequestId,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<CancelRideRequestResponse>(
        '$_rideRequestBasePath/cancel-request/$tempRequestId/',
        fromJson: CancelRideRequestResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Get trips for the authenticated user.
  /// Corresponds to GET /trip/user/
  static Future<ApiResponse<GetUserTripsResponse>> getUserTrips() {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.get<GetUserTripsResponse>(
        '$_tripBasePath/user/trips/',
        fromJson: GetUserTripsResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Get the currently active trip (for recovering state after app restart).
  /// Corresponds to GET /trip/active/
  static Future<ApiResponse<ActiveTripResponse>> getActiveTrip() {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.get<ActiveTripResponse>(
        '$_tripBasePath/active/',
        fromJson: ActiveTripResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Poll request status when WebSocket is unavailable.
  /// Corresponds to GET /riderequest/status/<temp_request_id>/
  static Future<ApiResponse<RequestStatusResponse>> getRequestStatus(
    String tempRequestId,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.get<RequestStatusResponse>(
        '$_rideRequestBasePath/status/$tempRequestId/',
        fromJson: RequestStatusResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Request a ride using Stripe Payment Sheet flow.
  /// Corresponds to POST /riderequest/request-with-payment/
  static Future<ApiResponse<RequestRideWithPaymentResponse>>
  requestRideWithPayment(RideRequestWithPaymentRequest request) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<RequestRideWithPaymentResponse>(
        '$_rideRequestBasePath/request-with-payment/',
        body: request.toJson(),
        fromJson: RequestRideWithPaymentResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Confirm the bike is unlocked and transition trip to on-trip state.
  /// Corresponds to POST /trip/begin/<trip_id>/
  static Future<ApiResponse<BeginTripResponse>> beginTrip(String tripId) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<BeginTripResponse>(
        '$_tripBasePath/begin/$tripId/',
        fromJson: BeginTripResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Rate a completed trip.
  /// Corresponds to POST /trip/<trip_id>/rate/
  static Future<ApiResponse<RateTripResponse>> rateTrip(
    String tripId,
    RateTripRequest request,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<RateTripResponse>(
        '$_tripBasePath/$tripId/rate/',
        body: request.toJson(),
        fromJson: RateTripResponse.fromJson,
        auth: true,
      );
    });
  }

  /// Get nearby available bikes.
  /// Corresponds to GET /bikes/nearby/
  static Future<ApiResponse<List<NearbyBike>>> getNearbyBikes({
    required double latitude,
    required double longitude,
    double? radius,
  }) async {
    final Map<String, String> params = {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
    };
    if (radius != null) {
      params['radius'] = radius.toString();
    }

    final apiResponse = await BaseApiService.get<List<dynamic>>(
      // Expecting List<dynamic>
      '$_bikesBasePath/nearby/',
      params: params,
      auth: true, // Assuming this is now true
      fromJson: null,
    );

    if (apiResponse.success && apiResponse.data != null) {
      try {
        // Log the raw data and its type
        print(
          'RideApiService: Raw apiResponse.data type: ${apiResponse.data.runtimeType}',
        );
        print(
          'RideApiService: Raw apiResponse.data value: ${apiResponse.data}',
        );

        // Ensure apiResponse.data is actually a List
        if (apiResponse.data is! List) {
          print(
            'RideApiService: ERROR - apiResponse.data is not a List, but ${apiResponse.data.runtimeType}',
          );
          return ApiResponse.error(
            'Failed to parse nearby bikes data: Expected a List but got ${apiResponse.data.runtimeType}',
            statusCode: apiResponse.statusCode,
          );
        }

        final List<dynamic> rawItems = apiResponse.data as List<dynamic>;
        final List<NearbyBike> bikes = [];

        for (int i = 0; i < rawItems.length; i++) {
          final item = rawItems[i];
          print(
            'RideApiService: Processing item at index $i, type: ${item.runtimeType}, value: $item',
          );
          if (item is Map<String, dynamic>) {
            // Wrap individual fromJson call in a try-catch to pinpoint which item fails
            try {
              bikes.add(NearbyBike.fromJson(item));
            } catch (e, s) {
              print('RideApiService: ERROR parsing item at index $i: $item');
              print('RideApiService: Individual item parsing error: $e');
              print('RideApiService: Individual item parsing stack trace: $s');
              // Re-throw to be caught by the outer catch, or handle differently
              throw FormatException(
                'Error parsing bike at index $i: ${e.toString()}',
              );
            }
          } else {
            print(
              'RideApiService: ERROR - Item at index $i is not a Map<String, dynamic>, but ${item.runtimeType}',
            );
            throw FormatException(
              'Encountered an item in the list (index $i) that is not a Map: ${item.runtimeType}',
            );
          }
        }
        return ApiResponse.success(bikes);
      } catch (e, s) {
        // Catch the exception and print stack trace
        print('RideApiService: Overall parsing error: $e');
        print('RideApiService: Overall parsing stack trace: $s');
        return ApiResponse.error(
          'Failed to parse nearby bikes data: ${e.toString()}',
          statusCode: apiResponse.statusCode,
        );
      }
    } else {
      return ApiResponse.error(
        apiResponse.error ??
            'Failed to fetch nearby bikes (apiResponse not success or data is null)',
        statusCode: apiResponse.statusCode,
      );
    }
  }
}
