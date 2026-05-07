import 'package:paddleapp/Apiendpoints/models/api_response.dart';

import '../models/auth_models.dart';
import 'base_api_service.dart';
import 'token_storage_service.dart';

class AuthApiService {
  static Future<ApiResponse<LoginResponse>> login(LoginRequest request) async {
    final response = await BaseApiService.post<Map<String, dynamic>>(
      '/rider/login/',
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
      '/rider/register/',
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
      '/rider/register/',
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
      '/rider/logout/',
      body: request.toJson(),
      auth: true,
    );
    // Clear tokens locally regardless — even if server-side blacklisting fails,
    // the device should not retain credentials.
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
    final response = await BaseApiService.requestWithRetry<
      Map<String, dynamic>
    >(() => BaseApiService.get('/rider/token/check/', auth: true));
    return response.success;
  }

  static Future<ApiResponse<User>> getProfile() async {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.get<User>(
        '/rider/profile/',
        fromJson: User.fromJson,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<User>> updateProfile(
    UpdateProfileRequest request,
  ) async {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.put<User>(
        '/rider/profile/update/',
        body: request.toJson(),
        fromJson: User.fromJson,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<void>> deleteProfile() async {
    try {
      final response = await BaseApiService.delete<void>(
        '/rider/profile/delete/',
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

  static Future<ApiResponse<Map<String, dynamic>>> updateLocation(
    LocationUpdateRequest request,
  ) async {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '/rider/location/update/',
        body: request.toJson(),
        fromJson: (json) => json,
        auth: true,
      );
    });
  }

  // Returns LoginResponse on success; throws SocialRegistrationNeeded if
  // the server signals the user has no account yet.
  static Future<ApiResponse<LoginResponse>> socialLogin(
    Map<String, dynamic> socialRequest, {
    void Function(SocialRegistrationNeeded)? onNeedsRegistration,
  }) async {
    final response = await BaseApiService.post<Map<String, dynamic>>(
      '/rider/login/',
      body: socialRequest,
      auth: false,
    );

    if (response.success && response.data != null) {
      final data = response.data!;
      // Backend signals new user — not an error, just a redirect
      if (data['needs_registration'] == true) {
        final reg = SocialRegistrationNeeded.fromJson(data);
        onNeedsRegistration?.call(reg);
        return ApiResponse.error('needs_registration');
      }
      try {
        final loginResp = LoginResponse.fromJson(data);
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
        '/rider/register/',
        body: socialRequest,
        fromJson: RegisterPhase1Response.fromJson,
        auth: false,
      );
    });
  }

  static Future<ApiResponse<Map<String, dynamic>>> setupPaymentMethod() async {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '/rider/payment/setup/',
        fromJson: (json) => json,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<Map<String, dynamic>>> confirmPaymentMethod({
    String? paymentMethodId,
    String? setupIntentClientSecret,
  }) async {
    return BaseApiService.requestWithRetry(() async {
      return BaseApiService.post<Map<String, dynamic>>(
        '/rider/payment/confirm/',
        body: {
          if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
          if (setupIntentClientSecret != null)
            'setup_intent_client_secret': setupIntentClientSecret,
        },
        fromJson: (json) => json,
        auth: true,
      );
    });
  }

  static Future<ApiResponse<MessageResponse>> forgotPassword(String email) =>
      BaseApiService.post(
        '/rider/password/forgot/',
        body: {'email': email},
        fromJson: MessageResponse.fromJson,
        auth: false,
      );

  static Future<ApiResponse<ResetTokenResponse>> verifyResetOtp(
    String email,
    String otp,
  ) =>
      BaseApiService.post(
        '/rider/password/verify-otp/',
        body: {'email': email, 'otp': otp},
        fromJson: ResetTokenResponse.fromJson,
        auth: false,
      );

  static Future<ApiResponse<MessageResponse>> resetPassword(
    String resetToken,
    String newPassword,
  ) =>
      BaseApiService.post(
        '/rider/password/reset/',
        body: {'reset_token': resetToken, 'new_password': newPassword},
        fromJson: MessageResponse.fromJson,
        auth: false,
      );

  static Future<ApiResponse<MessageResponse>> changePassword(
    String oldPassword,
    String newPassword,
  ) =>
      BaseApiService.requestWithRetry(
        () => BaseApiService.post(
          '/rider/password/change/',
          body: {'old_password': oldPassword, 'new_password': newPassword},
          fromJson: MessageResponse.fromJson,
          auth: true,
        ),
      );

  static Future<ApiResponse<Map<String, dynamic>>> listPaymentMethods() =>
      BaseApiService.requestWithRetry(
        () => BaseApiService.get<Map<String, dynamic>>(
          '/rider/payment/methods/',
          fromJson: (json) => json as Map<String, dynamic>,
          auth: true,
        ),
      );

  static Future<ApiResponse<MessageResponse>> deletePaymentMethod(
          String pmId) =>
      BaseApiService.requestWithRetry(
        () => BaseApiService.delete<MessageResponse>(
          '/rider/payment/method/$pmId/delete/',
          fromJson: MessageResponse.fromJson,
          auth: true,
        ),
      );

  /// Upload a new profile picture for the rider.
  /// [imagePath] is the absolute path to the local image file.
  static Future<ApiResponse<MessageResponse>> updateProfilePicture(
    String imagePath,
  ) =>
      BaseApiService.requestWithRetry(
        () => BaseApiService.patchMultipart<MessageResponse>(
          '/rider/profile/update/',
          fields: const {},
          filePaths: {'profile_picture': imagePath},
          fromJson: MessageResponse.fromJson,
          auth: true,
        ),
      );

  /// Fetch the rider's notification history.
  static Future<ApiResponse<Map<String, dynamic>>> getNotificationHistory({
    int limit = 50,
    int offset = 0,
    bool unreadOnly = false,
  }) =>
      BaseApiService.requestWithRetry(
        () => BaseApiService.get<Map<String, dynamic>>(
          '/notifications/',
          params: {
            'limit': '$limit',
            'offset': '$offset',
            if (unreadOnly) 'unread': 'true',
          },
          fromJson: (json) => json,
          auth: true,
        ),
      );

  /// Mark notifications as read. Pass [ids] to mark specific ones, or omit to mark all.
  static Future<ApiResponse<Map<String, dynamic>>> markNotificationsRead({
    List<int>? ids,
  }) =>
      BaseApiService.requestWithRetry(
        () => BaseApiService.post<Map<String, dynamic>>(
          '/notifications/mark-read/',
          body: ids != null ? {'ids': ids} : {},
          fromJson: (json) => json,
          auth: true,
        ),
      );
}
