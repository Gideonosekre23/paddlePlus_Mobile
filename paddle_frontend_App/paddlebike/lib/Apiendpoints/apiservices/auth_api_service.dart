import 'package:paddlebike/Apiendpoints/models/api_response.dart';

import '../models/auth_models.dart';
import 'base_api_service.dart';
import 'token_storage_service.dart';

class AuthApiService {
  static Future<ApiResponse<LoginResponse>> login(LoginRequest request) async {
    final response = await BaseApiService.post<Map<String, dynamic>>(
      '/owner/login/',
      body: request.toJson(),
      auth: false,
    );

    if (response.success && response.data != null) {
      try {
        final loginResp = LoginResponse.fromJson(response.data!);
        return ApiResponse.success(loginResp);
      } catch (e) {
        return ApiResponse.error('Parsing error: $e');
      }
    }
    return ApiResponse.error(response.error ?? 'Login failed');
  }

  static Future<ApiResponse<RegisterPhase1Response>> registerPhase1(
    RegisterPhase1Request request,
  ) async {
    final response = await BaseApiService.post<RegisterPhase1Response>(
      '/owner/register/',
      body: request.toJson(),
      auth: false,
      fromJson: RegisterPhase1Response.fromJson,
    );
    return response;
  }

  static Future<ApiResponse<RegisterPhase2Response>> registerPhase2(
    RegisterPhase2Request request,
  ) async {
    final response = await BaseApiService.post<RegisterPhase2Response>(
      '/owner/register/',
      body: request.toJson(),
      auth: false,
      fromJson: RegisterPhase2Response.fromJson,
    );
    return response;
  }

  static Future<ApiResponse<Map<String, dynamic>>> logout(
    String refreshToken,
  ) async {
    final request = LogoutRequest(refreshToken: refreshToken);
    final response = await BaseApiService.post<Map<String, dynamic>>(
      '/owner/logout/',
      body: request.toJson(),
      auth: true,
    );
    await TokenStorageService.clearTokens();
    return response;
  }

  static Future<ApiResponse<TokenResponse>> refreshToken() async {
    final refreshToken = await TokenStorageService.getRefreshToken();
    if (refreshToken == null) {
      return ApiResponse.error('No refresh token available');
    }
    final response = await BaseApiService.post<TokenResponse>(
      '/api/token/refresh/',
      body: {'refresh': refreshToken},
      auth: false,
      fromJson: TokenResponse.fromJson,
    );
    if (response.success && response.data != null) {
      await TokenStorageService.saveTokens(
        response.data!.accessToken,
        response.data!.refreshToken ?? refreshToken,
      );
    }
    return response;
  }

  static Future<bool> isAuthenticated() async {
    final response =
        await BaseApiService.requestWithRetry<Map<String, dynamic>>(
          () =>
              BaseApiService.post('/owner/check-token/', body: {}, auth: true),
        );
    return response.success;
  }

  static Future<ApiResponse<User>> updateProfile(
    UpdateProfileRequest request,
  ) async {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.put<User>(
        '/owner/profile/update/',
        body: request.toJson(),
        fromJson: User.fromJson,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<void>> deleteProfile() async {
    try {
      final response = await BaseApiService.delete<void>(
        '/owner/profile/delete/',
        fromJson: null,
        auth: true,
      );

      print(
        '📨 AuthApiService deleteProfile: Success=${response.success}, StatusCode=${response.statusCode}',
      );

      if (response.statusCode == 204) {
        print('✅ AuthApiService: 204 received - Account deleted successfully');
        return ApiResponse.success(null);
      }

      // Return the original response for other cases
      return response;
    } catch (e) {
      print('❌ AuthApiService deleteProfile error: $e');
      return ApiResponse.error('Failed to delete account: ${e.toString()}');
    }
  }

  // static Future<ApiResponse<Map<String, dynamic>>> updateLocation(
  //   LocationUpdateRequest request,
  // ) async {
  //   return BaseApiService.requestWithRetry(() async {
  //     return BaseApiService.post<Map<String, dynamic>>(
  //       '/rider/location/update/',
  //       body: request.toJson(),
  //       fromJson: (json) => json,
  //       auth: true,
  //     );
  //   });
  // }

  static Future<ApiResponse<LoginResponse>> socialLogin(
    Map<String, dynamic> socialRequest,
  ) async {
    final response = await BaseApiService.post<Map<String, dynamic>>(
      '/owner/login/',
      body: socialRequest,
      auth: false,
    );

    if (response.success && response.data != null) {
      try {
        final loginResp = LoginResponse.fromJson(response.data!);
        return ApiResponse.success(loginResp);
      } catch (e) {
        return ApiResponse.error('Parsing error: $e');
      }
    }
    return ApiResponse.error(response.error ?? 'Social login failed');
  }

  static Future<ApiResponse<RegisterPhase1Response>> socialRegister(
    Map<String, dynamic> socialRequest,
  ) {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<RegisterPhase1Response>(
        '/owner/register/',
        body: socialRequest,
        fromJson: RegisterPhase1Response.fromJson,
        auth: false,
      );
    });
  }
}
