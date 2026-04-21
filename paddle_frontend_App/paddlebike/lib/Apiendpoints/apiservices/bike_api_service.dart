import 'package:paddlebike/Apiendpoints/models/bike_model.dart';

import '../models/api_response.dart';

import 'base_api_service.dart';

class BikeApiService {
  static const String _bikesBasePath = '/bikes';

  static Future<ApiResponse<AddBikeResponse>> addBike(AddBikeRequest request) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<AddBikeResponse>(
        '$_bikesBasePath/add/',
        body: request.toJson(),
        fromJson: AddBikeResponse.fromJson,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<GetOwnerBikesResponse>> getOwnerBikes() {
    return BaseApiService.requestWithRetry(() async {
      final apiResponse = await BaseApiService.get<List<dynamic>>(
        '$_bikesBasePath/owner/',
        auth: true,
        fromJson: null,
      );

      if (apiResponse.success && apiResponse.data != null) {
        try {
          final response = GetOwnerBikesResponse.fromJson(apiResponse.data!);
          return ApiResponse.success(response);
        } catch (e) {
          return ApiResponse.error(
            'Failed to parse bikes data: ${e.toString()}',
            statusCode: apiResponse.statusCode,
          );
        }
      } else {
        return ApiResponse.error(
          apiResponse.error ?? 'Failed to fetch owner bikes',
          statusCode: apiResponse.statusCode,
        );
      }
    });
  }

  static Future<ApiResponse<ActivateBikeResponse>> activateBike(
    int bikeId,
    ActivateBikeRequest request,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<ActivateBikeResponse>(
        '$_bikesBasePath/activate/$bikeId/',
        body: request.toJson(),
        fromJson: ActivateBikeResponse.fromJson,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<ToggleBikeResponse>> toggleBikeAvailability(
    int bikeId,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<ToggleBikeResponse>(
        '$_bikesBasePath/toggle/$bikeId/',
        fromJson: ToggleBikeResponse.fromJson,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<RemoveBikeResponse>> removeBike(int bikeId) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.delete<RemoveBikeResponse>(
        '$_bikesBasePath/remove/$bikeId/',
        fromJson: RemoveBikeResponse.fromJson,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<List<Bike>>> getBikesByStatus(String status) async {
    final response = await getOwnerBikes();

    if (response.success && response.data != null) {
      final filteredBikes = response.data!.bikes
          .where((bike) => bike.bikeStatus == status)
          .toList();

      return ApiResponse.success(filteredBikes);
    }

    return ApiResponse.error(
      response.error ?? 'Failed to get bikes by status',
      statusCode: response.statusCode,
    );
  }

  /// Get bikes that need activation
  static Future<ApiResponse<List<Bike>>> getBikesNeedingActivation() async {
    final response = await getOwnerBikes();

    if (response.success && response.data != null) {
      final inactiveBikes = response.data!.bikes
          .where((bike) => bike.needsActivation)
          .toList();

      return ApiResponse.success(inactiveBikes);
    }

    return ApiResponse.error(
      response.error ?? 'Failed to get inactive bikes',
      statusCode: response.statusCode,
    );
  }

  /// Get bikes ready for riders
  static Future<ApiResponse<List<Bike>>> getAvailableBikes() async {
    final response = await getOwnerBikes();

    if (response.success && response.data != null) {
      final availableBikes = response.data!.bikes
          .where((bike) => bike.isReadyForRiders)
          .toList();

      return ApiResponse.success(availableBikes);
    }

    return ApiResponse.error(
      response.error ?? 'Failed to get available bikes',
      statusCode: response.statusCode,
    );
  }

  /// Get bike statistics summary
  static Future<ApiResponse<BikesSummary>> getBikesSummary() async {
    final response = await getOwnerBikes();

    if (response.success && response.data != null) {
      return ApiResponse.success(response.data!.summary);
    }

    return ApiResponse.error(
      response.error ?? 'Failed to get bikes summary',
      statusCode: response.statusCode,
    );
  }

  /// Check if bike can be activated (exists and is inactive)
  static Future<ApiResponse<bool>> canActivateBike(int bikeId) async {
    final response = await getOwnerBikes();

    if (response.success && response.data != null) {
      final bike = response.data!.bikes
          .where((b) => b.id == bikeId)
          .firstOrNull;

      if (bike == null) {
        return ApiResponse.error('Bike not found');
      }

      if (bike.isActive) {
        return ApiResponse.error('Bike is already activated');
      }

      return ApiResponse.success(true);
    }

    return ApiResponse.error(
      response.error ?? 'Failed to check bike status',
      statusCode: response.statusCode,
    );
  }

  /// Check if bike can be toggled (exists and is active)
  static Future<ApiResponse<bool>> canToggleBike(int bikeId) async {
    final response = await getOwnerBikes();

    if (response.success && response.data != null) {
      final bike = response.data!.bikes
          .where((b) => b.id == bikeId)
          .firstOrNull;

      if (bike == null) {
        return ApiResponse.error('Bike not found');
      }

      if (!bike.isActive) {
        return ApiResponse.error('Bike must be activated first');
      }

      return ApiResponse.success(true);
    }

    return ApiResponse.error(
      response.error ?? 'Failed to check bike status',
      statusCode: response.statusCode,
    );
  }
}
