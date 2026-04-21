// User Profile
class UserProfile {
  final String username;
  final String email;
  final String? phoneNumber;
  final String? profilePicture;
  const UserProfile({
    required this.username,
    required this.email,
    this.phoneNumber,
    this.profilePicture,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    username: json['username'] as String,
    email: json['email'] as String,
    phoneNumber: json['phone_number'] as String?,
    profilePicture: json['profile_picture'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'username': username,
    'email': email,
    'phone_number': phoneNumber,
    'profile_picture': profilePicture,
  };

  bool get hasProfilePicture =>
      profilePicture != null && profilePicture!.isNotEmpty;
  String get displayName => username;
  String get initials => username.isNotEmpty ? username[0].toUpperCase() : 'U';
}

// Update Profile Request
class UpdateProfileRequest {
  final String? phoneNumber;
  final String? profilePicture;

  const UpdateProfileRequest({this.phoneNumber, this.profilePicture});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};

    if (phoneNumber != null) {
      data['phone_number'] = phoneNumber;
    }

    if (profilePicture != null) {
      data['profile_picture'] = profilePicture;
    }

    return data;
  }
}

// Profile Update Response
class ProfileUpdateResponse {
  final String message;

  const ProfileUpdateResponse({required this.message});

  factory ProfileUpdateResponse.fromJson(Map<String, dynamic> json) =>
      ProfileUpdateResponse(message: json['message'] as String);
}

// Profile Delete Response
class ProfileDeleteResponse {
  final String message;

  const ProfileDeleteResponse({required this.message});

  factory ProfileDeleteResponse.fromJson(Map<String, dynamic> json) =>
      ProfileDeleteResponse(message: json['message'] as String);
}
