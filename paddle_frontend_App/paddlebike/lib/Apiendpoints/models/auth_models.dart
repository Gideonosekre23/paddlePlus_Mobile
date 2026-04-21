// --- Registration Phase 1 ---

class RegisterPhase1Request {
  final String username;
  final String email;
  final String password;

  const RegisterPhase1Request({
    required this.username,
    required this.email,
    required this.password,
  });

  // Converts the model to a JSON map for the API request body
  Map<String, dynamic> toJson() => {
    'username': username,
    'email': email,
    'password': password,
  };
}

// Response body from the first registration step
class RegisterPhase1Response {
  final String message;
  final String token; // This token is for Phase 2 registration

  const RegisterPhase1Response({required this.message, required this.token});

  // Creates a model instance from a JSON map
  factory RegisterPhase1Response.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('message') || !json.containsKey('token')) {
      throw const FormatException(
        "Invalid JSON for RegisterPhase1Response: Missing keys",
      );
    }
    return RegisterPhase1Response(
      message: json['message'] as String,
      token: json['token'] as String,
    );
  }
}

// --- Registration Phase 2 ---

// Request body for the second registration step (additional info + token)
class RegisterPhase2Request {
  final String token; // Token received from Phase 1
  final String cpn;
  final String address;
  final String phoneNumber;
  final double? latitude;
  final double? longitude;
  final String? profilePicture; // Base64 encoded string or URL

  const RegisterPhase2Request({
    required this.token,
    required this.cpn,
    required this.address,
    required this.phoneNumber,
    required this.latitude,
    required this.longitude,
    this.profilePicture,
  });

  // Converts the model to a JSON map for the API request body
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'token': token,
      'cpn': cpn,
      'address': address,
      'phone_number': phoneNumber,
    };

    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (profilePicture != null) data['profile_picture'] = profilePicture;

    return data;
  }
}

class RegisterPhase2Response {
  final String message;
  final String verificationUrl;
  final String sessionId;
  final String websocketUrl;

  const RegisterPhase2Response({
    required this.message,
    required this.verificationUrl,
    required this.sessionId,
    required this.websocketUrl,
  });

  // Creates a model instance from a JSON map
  factory RegisterPhase2Response.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('message') ||
        !json.containsKey('verification_url') ||
        !json.containsKey('session_id') ||
        !json.containsKey('websocket_url')) {
      throw const FormatException(
        "Invalid JSON for RegisterPhase2Response: Missing keys",
      );
    }
    return RegisterPhase2Response(
      message: json['message'] as String,
      verificationUrl: json['verification_url'] as String,
      sessionId: json['session_id'] as String,
      websocketUrl: json['websocket_url'] as String,
    );
  }
}

class User {
  final int id;
  final String username;
  final String email;
  final String? phoneNumber;
  final String? address;
  final String? profilePicture;
  final String verificationStatus;
  final double? total_earnings;

  const User({
    required this.id,
    required this.username,
    required this.email,
    this.phoneNumber,
    this.address,
    this.total_earnings,
    this.profilePicture,
    required this.verificationStatus,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('username') ||
        !json.containsKey('email') ||
        !json.containsKey('verification_status')) {
      throw const FormatException(
        "Invalid JSON for User: Missing required keys",
      );
    }
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,

      phoneNumber: json.containsKey('phone_number')
          ? json['phone_number'] as String?
          : null,
      total_earnings: json.containsKey('total_earnings')
          ? (json['total_earnings'] as num?)?.toDouble()
          : null,
      address: json.containsKey('address') ? json['address'] as String? : null,
      profilePicture: json.containsKey('profile_picture')
          ? json['profile_picture'] as String?
          : null,
      verificationStatus: json['verification_status'] as String,
    );
  }

  // Method to convert User object to JSON for saving locally (e.g., in SharedPreferences)
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'id': id,
      'username': username,
      'email': email,
      'verification_status': verificationStatus,
    };
    if (phoneNumber != null) data['phone_number'] = phoneNumber;
    if (address != null) data['address'] = address;
    if (profilePicture != null) data['profile_picture'] = profilePicture;
    if (total_earnings != null) data['total_earnings'] = total_earnings;
    return data;
  }
}

// --- Login Request ---

class LoginRequest {
  final String? username;
  final String? email;
  final String? password;
  final String? provider;
  final String? token;

  const LoginRequest({
    this.username,
    this.email,
    this.password,
    this.provider,
    this.token,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    // Include fields only if they are not null
    if (username != null) data['username'] = username;
    if (email != null) data['email'] = email;
    if (password != null) data['password'] = password;
    if (provider != null) data['provider'] = provider;
    if (token != null) data['token'] = token;
    return data;
  }
}

// --- Login Response ---

class LoginResponse {
  final User user;

  final String accessToken;
  final String refreshToken;
  final String chatWsUrl;
  final String wsUrl;

  const LoginResponse({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.chatWsUrl,
    required this.wsUrl,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    // Ensure the 'user' key itself is present
    if (!json.containsKey('user')) {
      throw const FormatException(
        "Invalid JSON for LoginResponse: Missing 'user' key",
      );
    }

    // Access the nested user data
    final userData = json['user'] as Map<String, dynamic>;

    // Ensure all expected keys are present within the 'user' object
    if (!userData.containsKey('access') ||
        !userData.containsKey('refresh') ||
        !userData.containsKey('chat_ws_url') ||
        !userData.containsKey('ws_url') ||
        !userData.containsKey('id') ||
        !userData.containsKey('total_earnings')) {
      throw const FormatException(
        "Invalid JSON for LoginResponse: Missing token or WebSocket URL keys within the 'user' object",
      );
    }

    final cleanUserData = <String, dynamic>{
      'id': userData['id'],
      'username': userData['username'],
      'email': userData['email'],
      'phone_number': userData['phone_number'],
      'profile_picture': userData['profile_picture'],
      'verification_status': userData['verification_status'],
      'total_earnings': userData['total_earnings'],
    };

    return LoginResponse(
      user: User.fromJson(cleanUserData),
      accessToken: userData['access'] as String,
      refreshToken: userData['refresh'] as String,
      chatWsUrl: userData['chat_ws_url'] as String,
      wsUrl: userData['ws_url'] as String,
    );
  }
}

// --- Logout Request ---

class LogoutRequest {
  final String refreshToken; // Matches backend 'refresh'

  const LogoutRequest({required this.refreshToken});

  Map<String, dynamic> toJson() => {
    'refresh': refreshToken, // Matches backend 'refresh'
  };
}

// --- Token Refresh Response ---

class TokenResponse {
  final String accessToken; // Matches backend 'access'
  final String? refreshToken; // Backend might return a new refresh token too

  const TokenResponse({required this.accessToken, this.refreshToken});

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('access')) {
      throw const FormatException(
        "Invalid JSON for TokenResponse: Missing 'access' key",
      );
    }
    return TokenResponse(
      accessToken: json['access'] as String,
      refreshToken: json.containsKey('refresh')
          ? json['refresh'] as String?
          : null,
    );
  }
}

// --- WebSocket Verification Complete Message ---

class VerifiedUserData {
  final int id;
  final String username;
  final String email;
  final String? phoneNumber;
  final String? profilePicture;
  final String? address;
  final double? total_earnings;
  final String verificationStatus;
  final String accessToken;
  final String refreshToken;
  final String? chatWsUrl;
  final String? wsUrl;

  const VerifiedUserData({
    required this.id,
    required this.username,
    required this.email,
    this.phoneNumber,
    this.profilePicture,
    this.address,
    this.total_earnings,
    required this.verificationStatus,
    required this.accessToken,
    required this.refreshToken,
    this.chatWsUrl,
    this.wsUrl,
  });

  factory VerifiedUserData.fromJson(Map<String, dynamic> json) {
    // Check for core fields that should always be there after verification
    if (!json.containsKey('id') ||
        !json.containsKey('username') ||
        !json.containsKey('email') ||
        !json.containsKey('verification_status') ||
        !json.containsKey('access') ||
        !json.containsKey('refresh') ||
        !json.containsKey('total_earnings')) {
      throw FormatException(
        "Invalid JSON for VerifiedUserData: Missing core keys (username, email, verification_status, access, refresh). Received: $json",
      );
    }
    return VerifiedUserData(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      phoneNumber: json['phone_number'] as String?,
      profilePicture: json['profile_picture'] as String?,
      address: json['address'] as String?,
      total_earnings: (json['total_earnings'] as num?)?.toDouble(),
      verificationStatus: json['verification_status'] as String,
      accessToken: json['access'] as String,
      refreshToken: json['refresh'] as String,
      chatWsUrl: json['chat_ws_url'] as String?,
      wsUrl: json['ws_url'] as String?,
    );
  }
}

class VerificationCompleteMessage {
  final String type;
  final String status;
  final String message;
  final VerifiedUserData? user;

  const VerificationCompleteMessage({
    required this.type,
    required this.status,
    required this.message,
    this.user,
  });

  factory VerificationCompleteMessage.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('type') ||
        !json.containsKey('status') ||
        !json.containsKey('message')) {
      throw FormatException(
        "Invalid JSON for VerificationCompleteMessage: Missing keys (type, status, message). Received: $json",
      );
    }
    return VerificationCompleteMessage(
      type: json['type'] as String,
      status: json['status'] as String,
      message: json['message'] as String,
      user:
          json.containsKey('user') &&
              json['user'] != null &&
              json['status'] == 'verified'
          ? VerifiedUserData.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }
}

// --- Other Models (if needed, e.g., for profile updates) ---

// Example: Update Profile Reques
class UpdateProfileRequest {
  final String? username;
  final String? email;
  final String? phoneNumber;
  final String? address;
  final String? profilePicture; // Base64 encoded string or URL

  const UpdateProfileRequest({
    this.username,
    this.email,
    this.phoneNumber,
    this.address,
    this.profilePicture,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (username != null) data['username'] = username;
    if (email != null) data['email'] = email;
    if (phoneNumber != null) data['phone_number'] = phoneNumber;
    if (address != null) data['address'] = address;
    if (profilePicture != null) data['profile_picture'] = profilePicture;
    return data;
  }
}

// Example: Location Update Request
class LocationUpdateRequest {
  final double latitude;
  final double longitude;

  const LocationUpdateRequest({
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

// --- Delete Profile Request ---
class DeleteProfileRequest {
  final String? password;
  final String? reason;
  final bool confirmDeletion;

  const DeleteProfileRequest({
    this.password,
    this.reason,
    this.confirmDeletion = true,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {'confirm_deletion': confirmDeletion};
    if (password != null) data['password'] = password;
    if (reason != null) data['reason'] = reason;
    return data;
  }
}

// --- Delete Profile Response ---
class DeleteProfileResponse {
  final String message;
  final bool success;
  final String? backupData;

  const DeleteProfileResponse({
    required this.message,
    required this.success,
    this.backupData,
  });

  factory DeleteProfileResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('message')) {
      throw const FormatException(
        "Invalid JSON for DeleteProfileResponse: Missing 'message' key",
      );
    }

    return DeleteProfileResponse(
      message: json['message'] as String,
      success: json['success'] ?? true,
      backupData: json['backup_data'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'message': message,
    'success': success,
    if (backupData != null) 'backup_data': backupData,
  };
}
