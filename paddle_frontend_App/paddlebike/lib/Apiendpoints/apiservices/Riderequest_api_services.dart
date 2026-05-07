import '../models/api_response.dart';
import 'base_api_service.dart';

class RideRequestApiService {
  /// Accept a ride request

  static Future<ApiResponse<Map<String, dynamic>>> acceptRideRequest(
    String tempRequestId,
  ) async {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '/riderequest/accept/$tempRequestId/',
        auth: true,
        fromJson: (json) => json,
      );
    });
  }

  /// Decline a ride request

  static Future<ApiResponse<Map<String, dynamic>>> declineRideRequest(
    String tempRequestId,
  ) async {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '/riderequest/decline/$tempRequestId/',
        auth: true,
        fromJson: (json) => json,
      );
    });
  }

}
