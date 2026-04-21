import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for securely storing and retrieving authentication tokens.
class TokenStorageService {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  /// Retrieves the access token from secure storage.
  static Future<String?> getAccessToken() => _storage.read(key: _accessKey);

  /// Retrieves the refresh token from secure storage.
  static Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  /// Saves the access and refresh tokens to secure storage.
  static Future<void> saveTokens(String access, String refresh) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: access),
      _storage.write(key: _refreshKey, value: refresh),
    ]);
  }

  /// Clears the access and refresh tokens from secure storage.
  static Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}
