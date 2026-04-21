import 'package:shared_preferences/shared_preferences.dart';

class UserStorageService {
  // --- Private Keys for SharedPreferences ---
  static const String _userJsonKey = 'paddleplus_currentUserJson';
  static const String _mainWsPathKey = 'paddleplus_mainWsRelativePath';
  static const String _chatWsPathKey = 'paddleplus_chatWsRelativePath';

  static Future<bool> saveUserJson(String userJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_userJsonKey, userJson);
    } catch (e) {
      print('UserStorageService: Error saving user JSON: $e');
      return false;
    }
  }

  /// Returns the JSON string if found, otherwise null.
  static Future<String?> getUserJson() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userJsonKey);
    } catch (e) {
      print('UserStorageService: Error getting user JSON: $e');
      return null;
    }
  }

  /// Clears the stored user's profile data.
  static Future<bool> clearUserJson() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_userJsonKey);
    } catch (e) {
      print('UserStorageService: Error clearing user JSON: $e');
      return false;
    }
  }

  // --- WebSocket Connection Paths ---

  static Future<bool> saveWebSocketPaths(
    String mainPath,
    String? chatPath,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool mainSuccess = await prefs.setString(_mainWsPathKey, mainPath);
      bool chatSuccess = true;
      if (chatPath != null && chatPath.isNotEmpty) {
        chatSuccess = await prefs.setString(_chatWsPathKey, chatPath);
      } else {
        // If chatPath is null or empty, remove it from storage
        if (prefs.containsKey(_chatWsPathKey)) {
          chatSuccess = await prefs.remove(_chatWsPathKey);
        }
      }
      return mainSuccess && chatSuccess;
    } catch (e) {
      print('UserStorageService: Error saving WebSocket paths: $e');
      return false;
    }
  }

  /// Retrieves the stored relative path for the main WebSocket.

  static Future<String?> getMainWebSocketPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_mainWsPathKey);
    } catch (e) {
      print('UserStorageService: Error getting main WebSocket path: $e');
      return null;
    }
  }

  /// Retrieves the stored relative path for the chat WebSocket.

  static Future<String?> getChatWebSocketPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_chatWsPathKey);
    } catch (e) {
      print('UserStorageService: Error getting chat WebSocket path: $e');
      return null;
    }
  }

  /// Clears the stored WebSocket paths
  static Future<bool> clearWebSocketPaths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool mainClearSuccess = await prefs.remove(_mainWsPathKey);
      bool chatClearSuccess = true;
      if (prefs.containsKey(_chatWsPathKey)) {
        chatClearSuccess = await prefs.remove(_chatWsPathKey);
      }
      return mainClearSuccess ||
          chatClearSuccess; // Return true if at least one was cleared or didn't exist
    } catch (e) {
      print('UserStorageService: Error clearing WebSocket paths: $e');
      return false;
    }
  }

  static Future<void> clearAllUserData() async {
    print('UserStorageService: Clearing all user data...');
    try {
      await clearUserJson();
      await clearWebSocketPaths();
      // Add calls to clear other specific data here if needed in the future
      print('UserStorageService: All user data cleared.');
    } catch (e) {
      print('UserStorageService: Error clearing all user data: $e');
    }
  }
}
