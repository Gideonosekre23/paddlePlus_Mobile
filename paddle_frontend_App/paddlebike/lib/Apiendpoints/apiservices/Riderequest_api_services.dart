import '../models/api_response.dart';
import 'base_api_service.dart';

class RideRequestApiService {
  /// Accept a ride request

  static Future<ApiResponse<Map<String, dynamic>>> acceptRideRequest(
    String tempRequestId,
  ) async {
    print(
      "🔄 RideRequestApiService: Accepting ride request with ID: $tempRequestId",
    );

    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '/riderequest/accept/$tempRequestId/',
        body: {},
        auth: true,
        fromJson: (json) => json,
      );
    });
  }

  /// Decline a ride request

  static Future<ApiResponse<Map<String, dynamic>>> declineRideRequest(
    String tempRequestId,
  ) async {
    print(
      "🔄 RideRequestApiService: Declining ride request with ID: $tempRequestId",
    );

    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '/riderequest/decline/$tempRequestId/',
        body: {},
        auth: true,
        fromJson: (json) => json,
      );
    });
  }

  /// Get pending ride requests for the current bike owner
  /// GET /riderequest/pending/
  // static Future<ApiResponse<List<Map<String, dynamic>>>>
  // getPendingRequests() async {
  //   print("🔄 RideRequestApiService: Fetching pending ride requests");

  //   return BaseApiService.requestWithRetry(() async {
  //     final response = await BaseApiService.get<Map<String, dynamic>>(
  //       '/riderequest/pending/',
  //       auth: true,
  //       fromJson: (json) => json,
  //     );

  //     if (response.success && response.data != null) {
  //       final responseData = response.data!;

  //       if (responseData['pending_requests'] != null) {
  //         final List<dynamic> requestsList =
  //             responseData['pending_requests'] as List<dynamic>;
  //         final List<Map<String, dynamic>> notifications = requestsList
  //             .map((item) => item as Map<String, dynamic>)
  //             .toList();

  //         print(
  //           "✅ RideRequestApiService: Fetched ${notifications.length} pending requests",
  //         );
  //         return ApiResponse.success(notifications);
  //       } else {
  //         print("✅ RideRequestApiService: No pending requests found");
  //         return ApiResponse.success(<Map<String, dynamic>>[]);
  //       }
  //     }

  //     return ApiResponse.error(
  //       response.error ?? "Failed to fetch pending requests",
  //     );
  //   });
  // }

  // /// Check connection status
  // static Future<bool> checkConnection() async {
  //   try {
  //     final response = await BaseApiService.get<Map<String, dynamic>>(
  //       '/auth/check/',
  //       auth: true,
  //       fromJson: (json) => json,
  //     );

  //     bool isConnected = response.success;
  //     print(
  //       "🌐 RideRequestApiService: Connection check - ${isConnected ? 'Connected' : 'Disconnected'}",
  //     );
  //     return isConnected;
  //   } catch (e) {
  //     print("💥 RideRequestApiService: Connection check failed: $e");
  //     return false;
  //   }
  // }
}
