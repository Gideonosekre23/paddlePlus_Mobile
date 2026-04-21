import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/api_response.dart';
import 'token_storage_service.dart';
import 'dart:async';

class BaseApiService {
  static String get baseUrl {
    const String envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      print("Using API_BASE_URL from environment: $envUrl");
      return envUrl;
    }

    if (kDebugMode) {
      if (kIsWeb) {
        print("Using debug web fallback URL: http://localhost:8000");
        return 'http://localhost:8000';
      } else if (Platform.isAndroid) {
        // Physical device on same LAN — uses PC's local IP.
        // Override with --dart-define=API_BASE_URL=http://<ip>:8000 if your IP changes.
        print("Using debug Android fallback URL: http://192.168.1.7:8000");
        return 'http://192.168.1.7:8000';
      } else if (Platform.isIOS || Platform.isMacOS) {
        print("Using debug iOS/macOS fallback URL: http://localhost:8000");
        return 'http://localhost:8000';
      }

      print(
        "DEBUG_MODE: Platform not web, Android, iOS, or macOS. Falling through to production/default URL logic.",
      );
    }

    // In release builds, API_BASE_URL must be set via --dart-define=API_BASE_URL=https://...
    // Falls back to the Render deployment URL if the define is omitted.
    const String productionUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://paddle-backend.onrender.com',
    );

    if (!kDebugMode) {
      print("Using production URL: $productionUrl");
    } else {
      print(
        "Using fallback/production URL in debug mode (no specific platform match or env var): $productionUrl",
      );
    }
    return productionUrl;
  }

  // HTTP client instance
  static final _client = http.Client();

  // Request timeout duration
  static const _timeout = Duration(seconds: 30);

  // --- Header Building ---

  /// Builds the standard headers for API requests, optionally including the Authorization token.
  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = {'Content-Type': 'application/json'};

    if (auth) {
      // Use the dedicated storage service to get the access token
      final token = await TokenStorageService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  // --- Response Handling ---

  /// Handles the HTTP response, parsing the body and returning an ApiResponse.
  static ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic>)? fromJson,
  ) {
    dynamic decodedBody;

    // Attempt to decode the body only if it's not empty.
    // An empty string is not valid JSON.
    if (response.body.isNotEmpty) {
      try {
        decodedBody = jsonDecode(response.body);
      } catch (e) {
        // JSON decoding failed.
        return ApiResponse.error(
          'Failed to decode response body. Status: ${response.statusCode}. Error: ${e.toString()}. Body: "${response.body}"',
          statusCode: response.statusCode,
        );
      }
    } else {
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          fromJson == null &&
          (T.toString() == 'List<dynamic>' ||
              T.toString().startsWith('List<NearbyBike>'))) {
        // Heuristic check for List types
        decodedBody = [];
      } else if (response.statusCode < 200 || response.statusCode >= 300) {
        decodedBody = null; // No body to parse for error messages
      } else {
        // For success codes but an empty body and not a recognized List<T> case
        return ApiResponse.error(
          'Response body was empty, but content was expected. Status: ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
    }

    switch (response.statusCode) {
      case 200: // OK
      case 201: // Created
        if (fromJson != null) {
          // Case 1: fromJson IS provided. It expects a Map<String, dynamic>.
          if (decodedBody is Map<String, dynamic>) {
            try {
              return ApiResponse.success(fromJson(decodedBody));
            } catch (e) {
              return ApiResponse.error(
                'Failed to parse success response data using fromJson: ${e.toString()}',
                statusCode: response.statusCode,
              );
            }
          } else {
            // fromJson was provided, but the decoded body isn't a Map. This is an error.
            return ApiResponse.error(
              'Expected JSON object for fromJson, but received ${decodedBody?.runtimeType}. Body: ${response.body}',
              statusCode: response.statusCode,
            );
          }
        } else {
          if (decodedBody is T) {
            // This runtime check is crucial.
            return ApiResponse.success(decodedBody);
          } else {
            return ApiResponse.error(
              'Type mismatch for success response. Expected type $T but received ${decodedBody?.runtimeType}. Body: ${response.body}',
              statusCode: response.statusCode,
            );
          }
        }
      case 204:
        if (null is T) {
          return ApiResponse.success(null as T);
        } else {
          return ApiResponse.error(
            'Received 204 No Content, but expected a non-nullable $T.',
            statusCode: response.statusCode,
          );
        }

      case 401: // Unauthorized
        String authErrorMessage = 'Session expired. Please login again.';
        if (decodedBody is Map<String, dynamic>) {
          authErrorMessage =
              decodedBody['detail']?.toString() ??
              decodedBody['error']?.toString() ??
              decodedBody['message']?.toString() ??
              authErrorMessage;
        }
        return ApiResponse.error(authErrorMessage, statusCode: 401);
      case 400: // Bad Request
      case 403: // Forbidden
      case 404: // Not Found
      case 422: // Unprocessable Entity
        String errorMessage =
            'An error occurred: ${response.reasonPhrase}'; // Default to reason phrase
        if (decodedBody is Map<String, dynamic>) {
          errorMessage =
              decodedBody['detail']?.toString() ??
              decodedBody['error']?.toString() ??
              decodedBody['message']?.toString() ??
              // Try to join multiple errors if it's a validation dict
              (decodedBody.entries.isNotEmpty
                  ? decodedBody.entries
                      .map(
                        (e) =>
                            '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}',
                      )
                      .join('; ')
                  : errorMessage);
        } else if (decodedBody != null && response.body.isNotEmpty) {
          errorMessage = decodedBody.toString();
        }
        return ApiResponse.error(errorMessage, statusCode: response.statusCode);
      default: // Other 5xx server errors or unhandled client errors
        String defaultErrorMessage =
            'Server error: ${response.statusCode} ${response.reasonPhrase}';
        if (decodedBody is Map<String, dynamic>) {
          defaultErrorMessage =
              decodedBody['detail']?.toString() ??
              decodedBody['error']?.toString() ??
              decodedBody['message']?.toString() ??
              defaultErrorMessage;
        } else if (decodedBody != null && response.body.isNotEmpty) {
          defaultErrorMessage = decodedBody.toString();
        }
        return ApiResponse.error(
          defaultErrorMessage,
          statusCode: response.statusCode,
        );
    }
  }

  // --- Exception Handling ---

  /// Handles network and other exceptions during the API call.
  static ApiResponse<T> _handleError<T>(dynamic error) {
    if (error is SocketException) {
      // No internet connection or host unreachable
      return ApiResponse.error(
        'No internet connection',
        statusCode: 0,
      ); // Use 0 for network errors
    }
    if (error.toString().contains('TimeoutException')) {
      // Request took too long
      return ApiResponse.error('Request timeout', statusCode: 408);
    }
    // Catch other potential http client exceptions
    if (error is http.ClientException) {
      return ApiResponse.error('HTTP Client Error: ${error.message}');
    }
    // Generic error for anything else
    return ApiResponse.error('Network error: ${error.toString()}');
  }

  // --- HTTP Methods ---

  /// Performs an HTTP GET request.
  static Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, String>? params,
    bool auth = true,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl$endpoint',
      ).replace(queryParameters: params);
      final headers = await _headers(auth: auth);

      final response = await _client
          .get(uri, headers: headers)
          .timeout(_timeout); // Apply timeout
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  /// Performs an HTTP POST request.
  static Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    bool auth = true,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = await _headers(auth: auth);
      final jsonBody = body != null ? jsonEncode(body) : null;

      final response = await _client
          .post(uri, headers: headers, body: jsonBody)
          .timeout(_timeout); // Apply timeout
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  /// Performs an HTTP PUT request.
  static Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    bool auth = true,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = await _headers(auth: auth);
      final jsonBody = body != null ? jsonEncode(body) : null;

      final response = await _client
          .put(uri, headers: headers, body: jsonBody)
          .timeout(_timeout); // Apply timeout
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  /// Performs an HTTP DELETE request.
  static Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    bool auth = true,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = await _headers(auth: auth);

      final response = await _client
          .delete(uri, headers: headers)
          .timeout(_timeout); // Apply timeout
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return _handleError<T>(e);
    }
  }

  // --- Token Refresh and Retry ---

  /// Attempts to refresh the access token using the stored refresh token.
  /// Returns true if successful, false otherwise.
  static Future<bool> refreshToken() async {
    try {
      // Use the dedicated storage service to get the refresh token
      final refresh = await TokenStorageService.getRefreshToken();
      if (refresh == null) {
        // No refresh token available, cannot refresh
        return false;
      }

      // Use the post method, but explicitly set auth to false for the refresh endpoint
      final response = await post<Map<String, dynamic>>(
        '/api/token/refresh/',
        body: {'refresh': refresh},
        auth: false,
      );

      if (response.success && response.data != null) {
        final newAccess = response.data!['access'] as String?;

        final newRefresh = response.data!['refresh'] as String?;

        if (newAccess != null) {
          // Save the new access token and potentially a new refresh token
          await TokenStorageService.saveTokens(
            newAccess,
            newRefresh ?? refresh,
          );
          return true; // Token refreshed successfully
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<ApiResponse<T>> requestWithRetry<T>(
    Future<ApiResponse<T>> Function() request,
  ) async {
    // First attempt
    var response = await request();

    if (!response.success && response.statusCode == 401) {
      // Attempt to refresh the token
      final refreshed = await refreshToken();

      if (refreshed) {
        // If token refreshed successfully, retry the original request
        // This second response is the one we should return
        response = await request();
        // Now 'response' holds the result of the successful retry (or whatever the second attempt yielded)
      }
      // If refresh failed, 'response' still holds the original 401 error response
    }

    return response;
  }
}
