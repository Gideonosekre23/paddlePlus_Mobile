class RideRequestNotification {
  final String tempRequestId;
  final String notificationType;
  final String title;
  final String message;
  final RideRequestData data;
  final DateTime receivedAt;

  RideRequestNotification({
    required this.tempRequestId,
    required this.notificationType,
    required this.title,
    required this.message,
    required this.data,
    required this.receivedAt,
  });

  factory RideRequestNotification.fromJson(Map<String, dynamic> json) {
    return RideRequestNotification(
      tempRequestId: json['data']['temp_request_id'] ?? '',
      notificationType: json['data']['notification_type'] ?? 'ride_request',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      data: RideRequestData.fromJson(json['data'] ?? {}),
      receivedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temp_request_id': tempRequestId,
      'notification_type': notificationType,
      'title': title,
      'message': message,
      'data': data.toJson(),
      'received_at': receivedAt.toIso8601String(),
    };
  }
}

class RideRequestData {
  final String tempRequestId;
  final RiderInfo riderInfo;
  final TripDetails tripDetails;
  final BikeInfo bikeInfo;
  final PaymentInfo paymentInfo;
  final String requestedTime;
  final int expiresInSeconds;

  RideRequestData({
    required this.tempRequestId,
    required this.riderInfo,
    required this.tripDetails,
    required this.bikeInfo,
    required this.paymentInfo,
    required this.requestedTime,
    this.expiresInSeconds = 300, // 5 minutes default
  });

  factory RideRequestData.fromJson(Map<String, dynamic> json) {
    return RideRequestData(
      tempRequestId: json['temp_request_id'] ?? '',
      riderInfo: RiderInfo.fromJson(json['rider_info'] ?? {}),
      tripDetails: TripDetails.fromJson(json['trip_details'] ?? {}),
      bikeInfo: BikeInfo.fromJson(json['bike_info'] ?? {}),
      paymentInfo: PaymentInfo.fromJson(json['payment_info'] ?? {}),
      requestedTime: json['requested_time'] ?? DateTime.now().toIso8601String(),
      expiresInSeconds: json['expires_in_seconds'] ?? 300,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temp_request_id': tempRequestId,
      'rider_info': riderInfo.toJson(),
      'trip_details': tripDetails.toJson(),
      'bike_info': bikeInfo.toJson(),
      'payment_info': paymentInfo.toJson(),
      'requested_time': requestedTime,
      'expires_in_seconds': expiresInSeconds,
    };
  }

  // Helper getters
  String get formattedPrice => '€${paymentInfo.totalAmount.toStringAsFixed(2)}';
  String get formattedDistance =>
      '${tripDetails.distance.toStringAsFixed(1)} km';
  String get estimatedDuration =>
      '${(tripDetails.distance / 15).toStringAsFixed(0)} min'; // 15 km/h average

  DateTime get requestedDateTime {
    try {
      return DateTime.parse(requestedTime);
    } catch (e) {
      return DateTime.now();
    }
  }

  DateTime get expiresAt =>
      requestedDateTime.add(Duration(seconds: expiresInSeconds));
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  int get remainingSeconds =>
      expiresAt.difference(DateTime.now()).inSeconds.clamp(0, expiresInSeconds);
}

class RiderInfo {
  final int riderId;
  final String username;
  final String? profilePicture;
  final String? phoneNumber;
  final double? rating;
  final int totalTrips;

  RiderInfo({
    required this.riderId,
    required this.username,
    this.profilePicture,
    this.phoneNumber,
    this.rating,
    this.totalTrips = 0,
  });

  factory RiderInfo.fromJson(Map<String, dynamic> json) {
    return RiderInfo(
      riderId: json['rider_id'] ?? 0,
      username: json['username'] ?? 'Unknown Rider',
      profilePicture: json['profile_picture'],
      phoneNumber: json['phone_number'],
      rating: json['rating']?.toDouble(),
      totalTrips: json['total_trips'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rider_id': riderId,
      'username': username,
      'profile_picture': profilePicture,
      'phone_number': phoneNumber,
      'rating': rating,
      'total_trips': totalTrips,
    };
  }

  // Helper getters
  String get displayName => username.isNotEmpty ? username : 'Rider';
  String get initials => username.isNotEmpty ? username[0].toUpperCase() : 'R';
  String get formattedRating =>
      rating != null ? '⭐ ${rating!.toStringAsFixed(1)}' : 'New rider';
  String get experienceText =>
      totalTrips > 0 ? '$totalTrips trips' : 'First trip';
}

class TripDetails {
  final double pickupLatitude;
  final double pickupLongitude;
  final double destinationLatitude;
  final double destinationLongitude;
  final String originAddress;
  final String destinationAddress;
  final double distance;
  final int durationHours;

  TripDetails({
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.originAddress,
    required this.destinationAddress,
    required this.distance,
    this.durationHours = 1,
  });

  factory TripDetails.fromJson(Map<String, dynamic> json) {
    return TripDetails(
      pickupLatitude: json['pickup_latitude']?.toDouble() ?? 0.0,
      pickupLongitude: json['pickup_longitude']?.toDouble() ?? 0.0,
      destinationLatitude: json['destination_latitude']?.toDouble() ?? 0.0,
      destinationLongitude: json['destination_longitude']?.toDouble() ?? 0.0,
      originAddress: json['origin_address'] ?? 'Unknown pickup location',
      destinationAddress: json['destination_address'] ?? 'Unknown destination',
      distance: json['distance']?.toDouble() ?? 0.0,
      durationHours: json['duration_hours'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pickup_latitude': pickupLatitude,
      'pickup_longitude': pickupLongitude,
      'destination_latitude': destinationLatitude,
      'destination_longitude': destinationLongitude,
      'origin_address': originAddress,
      'destination_address': destinationAddress,
      'distance': distance,
      'duration_hours': durationHours,
    };
  }

  // Helper getters
  String get shortOriginAddress {
    if (originAddress.length <= 30) return originAddress;
    return '${originAddress.substring(0, 27)}...';
  }

  String get shortDestinationAddress {
    if (destinationAddress.length <= 30) return destinationAddress;
    return '${destinationAddress.substring(0, 27)}...';
  }
}

class BikeInfo {
  final int bikeId;
  final String bikeName;
  final String brand;
  final String model;
  final String? color;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final int? batteryLevel;

  BikeInfo({
    required this.bikeId,
    required this.bikeName,
    required this.brand,
    required this.model,
    this.color,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
    this.batteryLevel,
  });

  factory BikeInfo.fromJson(Map<String, dynamic> json) {
    return BikeInfo(
      bikeId: json['bike_id'] ?? 0,
      bikeName: json['bike_name'] ?? 'Unknown Bike',
      brand: json['brand'] ?? 'Unknown',
      model: json['model'] ?? 'Unknown',
      color: json['color'],
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      imageUrl: json['image_url'],
      batteryLevel: json['battery_level'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bike_id': bikeId,
      'bike_name': bikeName,
      'brand': brand,
      'model': model,
      'color': color,
      'latitude': latitude,
      'longitude': longitude,
      'image_url': imageUrl,
      'battery_level': batteryLevel,
    };
  }

  // Helper getters
  String get displayName => bikeName.isNotEmpty ? bikeName : '$brand $model';
  String get fullDescription =>
      '$brand $model${color != null ? ' ($color)' : ''}';
  String get batteryDisplay => batteryLevel != null ? '🔋 $batteryLevel%' : '';
}

class PaymentInfo {
  final double totalAmount;
  final double ownerEarnings;
  final double platformCommission;
  final String paymentType;
  final String? paymentIntentId;

  PaymentInfo({
    required this.totalAmount,
    required this.ownerEarnings,
    required this.platformCommission,
    required this.paymentType,
    this.paymentIntentId,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      totalAmount: json['total_amount']?.toDouble() ?? 0.0,
      ownerEarnings: json['owner_earnings']?.toDouble() ?? 0.0,
      platformCommission: json['platform_commission']?.toDouble() ?? 0.0,
      paymentType: json['payment_type'] ?? 'card',
      paymentIntentId: json['payment_intent_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_amount': totalAmount,
      'owner_earnings': ownerEarnings,
      'platform_commission': platformCommission,
      'payment_type': paymentType,
      'payment_intent_id': paymentIntentId,
    };
  }

  // Helper getters
  String get formattedTotalAmount => '€${totalAmount.toStringAsFixed(2)}';
  String get formattedOwnerEarnings => '€${ownerEarnings.toStringAsFixed(2)}';
  String get formattedPlatformCommission =>
      '€${platformCommission.toStringAsFixed(2)}';
  bool get isRealPayment =>
      paymentIntentId != null && !paymentIntentId!.startsWith('sim_');
}

// 👈 ADD THIS MISSING CLASS - This was causing your error!
class RideRequestResponse {
  final bool success;
  final String message;
  final String? tripId;
  final String? rideRequestId;
  final String? chatRoomId;
  final Map<String, dynamic>? additionalData;

  RideRequestResponse({
    required this.success,
    required this.message,
    this.tripId,
    this.rideRequestId,
    this.chatRoomId,
    this.additionalData,
  });

  factory RideRequestResponse.fromJson(Map<String, dynamic> json) {
    return RideRequestResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      tripId: json['trip_id']?.toString(),
      rideRequestId: json['ride_request_id']?.toString(),
      chatRoomId: json['chat_room_id']?.toString(),
      additionalData: json,
    );
  }

  // 👈 THIS WAS MISSING - This fixes your error!
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'trip_id': tripId,
      'ride_request_id': rideRequestId,
      'chat_room_id': chatRoomId,
      ...?additionalData, // Spread additional data if present
    };
  }
}
