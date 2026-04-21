import 'package:flutter/material.dart';
import 'package:paddleapp/Apiendpoints/apiservices/base_api_service.dart';

class ImageUtils {
  static ImageProvider? getProfileImageProvider(String? profilePicture) {
    if (profilePicture == null || profilePicture.isEmpty) {
      return null;
    }

    try {
      if (profilePicture.startsWith('http')) {
        print("🖼️ Using full URL: $profilePicture");
        return NetworkImage(profilePicture);
      } else {
        final fullUrl = "${BaseApiService.baseUrl}$profilePicture";
        print("🔄 Converting to full URL: $fullUrl");
        return NetworkImage(fullUrl);
      }
    } catch (e) {
      print("❌ Error loading profile image: $e");
      return null;
    }
  }

  static Widget buildAvatar({
    required String? profilePicture,
    double radius = 30,
    IconData defaultIcon = Icons.person,
    VoidCallback? onError,
  }) {
    final imageProvider = getProfileImageProvider(profilePicture);

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[400],
      backgroundImage: imageProvider,
      onBackgroundImageError:
          imageProvider != null
              ? (exception, stackTrace) {
                print("Avatar Error for $profilePicture: $exception");
                if (onError != null) onError();
              }
              : null,
      child:
          imageProvider == null
              ? Icon(defaultIcon, size: radius, color: Colors.white)
              : null,
    );
  }
}
