import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for securely storing and retrieving authentication tokens.
class TokenStorageService {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  // In-memory fallback — flutter_secure_storage Web Crypto (SubtleCrypto) can
  // throw DOMException:OperationError on web; keeping tokens in memory avoids
  // that on the hot path while still persisting to secure storage for mobile.
  static String? _memAccess;
  static String? _memRefresh;

  static Future<String?> getAccessToken() async {
    if (kIsWeb && _memAccess != null) return _memAccess;
    try {
      return await _storage.read(key: _accessKey);
    } catch (_) {
      return _memAccess;
    }
  }

  static Future<String?> getRefreshToken() async {
    if (kIsWeb && _memRefresh != null) return _memRefresh;
    try {
      return await _storage.read(key: _refreshKey);
    } catch (_) {
      return _memRefresh;
    }
  }

  static Future<void> saveTokens(String access, String refresh) async {
    _memAccess = access;
    _memRefresh = refresh;
    await Future.wait([
      _storage.write(key: _accessKey, value: access),
      _storage.write(key: _refreshKey, value: refresh),
    ]);
  }

  static Future<void> clearTokens() async {
    _memAccess = null;
    _memRefresh = null;
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}
