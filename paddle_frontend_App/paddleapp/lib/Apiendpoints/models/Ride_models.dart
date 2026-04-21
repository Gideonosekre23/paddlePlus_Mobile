import 'dart:convert';

// --- Common Nested Models ---

class LocationPoint {
  final double latitude;
  final double longitude;

  const LocationPoint({required this.latitude, required this.longitude});

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('latitude') || !json.containsKey('longitude')) {
      throw const FormatException(
        "Invalid JSON for LocationPoint: Missing keys 'latitude' or 'longitude'",
      );
    }
    return LocationPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

// --- Estimate Price (POST /riderequest/estimate-price/) ---

class EstimatePriceRequest {
  final double pickupLatitude;
  final double pickupLongitude;
  final double destinationLatitude;
  final double destinationLongitude;

  const EstimatePriceRequest({
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
  });

  Map<String, dynamic> toJson() => {
    'pickup_latitude': pickupLatitude,
    'pickup_longitude': pickupLongitude,
    'destination_latitude': destinationLatitude,
    'destination_longitude': destinationLongitude,
  };
}

class PriceBreakdown {
  final String totalAmount;
  final String platformCommission;
  final String ownerEarnings;

  const PriceBreakdown({
    required this.totalAmount,
    required this.platformCommission,
    required this.ownerEarnings,
  });

  factory PriceBreakdown.fromJson(Map<String, dynamic> json) {
    return PriceBreakdown(
      totalAmount: json['total_amount'] as String,
      platformCommission: json['platform_commission'] as String,
      ownerEarnings: json['owner_earnings'] as String,
    );
  }
}

class NearestBikeEstimate {
  final int id;
  final String name;
  final String brand;
  final String model;
  final double distanceToBike;
  final LocationPoint location;

  const NearestBikeEstimate({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.distanceToBike,
    required this.location,
  });

  factory NearestBikeEstimate.fromJson(Map<String, dynamic> json) {
    return NearestBikeEstimate(
      id: json['id'] as int,
      name: json['name'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      distanceToBike: (json['distance_to_bike'] as num).toDouble(),
      location: LocationPoint.fromJson(
        json['location'] as Map<String, dynamic>,
      ),
    );
  }
}

class TripDetailsEstimate {
  final double distance;
  final double estimatedDurationHours;
  final double estimatedDurationMinutes;

  const TripDetailsEstimate({
    required this.distance,
    required this.estimatedDurationHours,
    required this.estimatedDurationMinutes,
  });

  factory TripDetailsEstimate.fromJson(Map<String, dynamic> json) {
    return TripDetailsEstimate(
      distance: (json['distance'] as num).toDouble(),
      estimatedDurationHours:
          (json['estimated_duration_hours'] as num).toDouble(),
      estimatedDurationMinutes:
          (json['estimated_duration_minutes'] as num).toDouble(),
    );
  }
}

class EstimatePriceResponse {
  final double estimatedPrice;
  final String priceToken;
  final int validUntil; // Unix timestamp
  final PriceBreakdown priceBreakdown;
  final NearestBikeEstimate nearestBike;
  final TripDetailsEstimate tripDetails;
  final String? warning;

  const EstimatePriceResponse({
    required this.estimatedPrice,
    required this.priceToken,
    required this.validUntil,
    required this.priceBreakdown,
    required this.nearestBike,
    required this.tripDetails,
    this.warning,
  });

  factory EstimatePriceResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('estimated_price') ||
        !json.containsKey('price_token') ||
        !json.containsKey('valid_until') ||
        !json.containsKey('price_breakdown') ||
        !json.containsKey('nearest_bike') ||
        !json.containsKey('trip_details')) {
      throw const FormatException(
        "Invalid JSON for EstimatePriceResponse: Missing one or more required keys.",
      );
    }
    return EstimatePriceResponse(
      estimatedPrice: (json['estimated_price'] as num).toDouble(),
      priceToken: json['price_token'] as String,
      validUntil: json['valid_until'] as int,
      priceBreakdown: PriceBreakdown.fromJson(
        json['price_breakdown'] as Map<String, dynamic>,
      ),
      nearestBike: NearestBikeEstimate.fromJson(
        json['nearest_bike'] as Map<String, dynamic>,
      ),
      tripDetails: TripDetailsEstimate.fromJson(
        json['trip_details'] as Map<String, dynamic>,
      ),
      warning: json['warning'] as String?,
    );
  }
}

class UserTripOwnerInfo {
  final String username;
  final int? id;

  const UserTripOwnerInfo({required this.username, this.id});

  factory UserTripOwnerInfo.fromJson(Map<String, dynamic> json) {
    return UserTripOwnerInfo(
      username: json['username'] as String,
      id: json['id'] as int?,
    );
  }
}

class UserTripBikeInfo {
  final String name;
  final String brand;
  final String model;
  final String color;
  final int? id;

  const UserTripBikeInfo({
    required this.name,
    required this.brand,
    required this.model,
    required this.color,
    this.id,
  });

  factory UserTripBikeInfo.fromJson(Map<String, dynamic> json) {
    return UserTripBikeInfo(
      name: json['name'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      color: json['color'] as String,
      id: json['id'] as int?,
    );
  }
}

class UserTripLocationInfo {
  final String address;
  final double? latitude;
  final double? longitude;

  const UserTripLocationInfo({
    required this.address,
    this.latitude,
    this.longitude,
  });

  factory UserTripLocationInfo.fromJson(Map<String, dynamic> json) {
    return UserTripLocationInfo(
      address: json['address'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

class UserTrip {
  final int id;
  final String bikeName;
  final UserTripBikeInfo bikeInfo;
  final UserTripOwnerInfo ownerInfo;
  final UserTripLocationInfo startLocation;
  final UserTripLocationInfo endLocation;
  final String? date;
  final String status;
  final double? price;
  final double? distance;
  final String paymentStatus;
  final String? createdAt;
  final int? riderRating;
  final String? riderReview;

  const UserTrip({
    required this.id,
    required this.bikeName,
    required this.bikeInfo,
    required this.ownerInfo,
    required this.startLocation,
    required this.endLocation,
    this.date,
    required this.status,
    this.price,
    this.distance,
    required this.paymentStatus,
    this.createdAt,
    this.riderRating,
    this.riderReview,
  });

  factory UserTrip.fromJson(Map<String, dynamic> json) {
    return UserTrip(
      id: json['id'] as int,
      bikeName: json['bike_name'] as String,
      bikeInfo: UserTripBikeInfo.fromJson(
        json['bike_info'] as Map<String, dynamic>,
      ),
      ownerInfo: UserTripOwnerInfo.fromJson(
        json['owner_info'] as Map<String, dynamic>,
      ),
      startLocation: UserTripLocationInfo.fromJson(
        json['start_location'] as Map<String, dynamic>,
      ),
      endLocation: UserTripLocationInfo.fromJson(
        json['end_location'] as Map<String, dynamic>,
      ),
      date: json['date'] as String?,
      status: json['status'] as String,
      price: (json['price'] as num?)?.toDouble(),
      distance: (json['distance'] as num?)?.toDouble(),
      paymentStatus: json['payment_status'] as String,
      createdAt: json['created_at'] as String?,
      riderRating: json['rider_rating'] as int?,
      riderReview: json['rider_review'] as String?,
    );
  }
}

// --- Unified Ride Request Response (handles success and bike-conflict cases) ---

class AlternativeBike {
  final int id;
  final String name;
  final String brand;
  final String model;
  final double distanceKm;
  final double latitude;
  final double longitude;
  final String? bikeImage;

  const AlternativeBike({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
    this.bikeImage,
  });

  factory AlternativeBike.fromJson(Map<String, dynamic> json) {
    final loc = json['location'] as Map<String, dynamic>? ?? {};
    return AlternativeBike(
      id: json['id'] as int,
      name: json['name'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      distanceKm: (json['distance_km'] as num).toDouble(),
      latitude: (loc['latitude'] as num).toDouble(),
      longitude: (loc['longitude'] as num).toDouble(),
      bikeImage: json['bike_image'] as String?,
    );
  }
}

class RideRequestResponse {
  final bool preferredBikeUnavailable;
  final String? tempRequestId;
  final String message;
  final AlternativeBike? alternativeBike;
  final String? newPriceToken;
  final double? estimatedPrice;

  const RideRequestResponse({
    required this.preferredBikeUnavailable,
    this.tempRequestId,
    required this.message,
    this.alternativeBike,
    this.newPriceToken,
    this.estimatedPrice,
  });

  factory RideRequestResponse.fromJson(Map<String, dynamic> json) {
    if (json['preferred_bike_unavailable'] == true) {
      return RideRequestResponse(
        preferredBikeUnavailable: true,
        message: json['message'] as String? ?? 'That bike was just taken.',
        alternativeBike: json['alternative_bike'] != null
            ? AlternativeBike.fromJson(
                json['alternative_bike'] as Map<String, dynamic>)
            : null,
        newPriceToken: json['new_price_token'] as String?,
        estimatedPrice: (json['estimated_price'] as num?)?.toDouble(),
      );
    }
    return RideRequestResponse(
      preferredBikeUnavailable: false,
      tempRequestId: json['temp_request_id'] as String,
      message: json['message'] as String,
    );
  }
}

class RideRequestRequest {
  final double pickupLatitude;
  final double pickupLongitude;
  final double destinationLatitude;
  final double destinationLongitude;
  final String destinationAddress;
  final String originAddress;
  final String paymentType; // e.g., "card"
  final String priceToken;

  const RideRequestRequest({
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.destinationAddress,
    required this.originAddress,
    required this.paymentType,
    required this.priceToken,
  });

  Map<String, dynamic> toJson() => {
    'pickup_latitude': pickupLatitude,
    'pickup_longitude': pickupLongitude,
    'destination_latitude': destinationLatitude,
    'destination_longitude': destinationLongitude,
    'destination_address': destinationAddress,
    'origin_address': originAddress,
    'payment_type': paymentType,
    'price_token': priceToken,
  };
}

// --- Start Trip (POST /trip/start/{trip_id}/) ---
class StartTripResponse {
  final String message;
  final String startTime; // ISO 8601 DateTime string

  const StartTripResponse({required this.message, required this.startTime});

  factory StartTripResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('message')) {
      throw const FormatException(
        "Invalid JSON for StartTripResponse: Missing 'message'.",
      );
    }
    return StartTripResponse(
      message: json['message'] as String,
      startTime: json['start_time']?.toString() ?? '',
    );
  }
}

// --- End Trip (POST /trip/end/{trip_id}/) ---
class TripDetailsEnd {
  final double durationHours;
  final double estimatedDistanceKm;
  final double actualDistanceKm;
  final double distanceDifferenceKm;
  final double estimatedPrice;
  final double extraCharge;
  final double finalPrice;
  final double commission;
  final double ownerPayout;

  const TripDetailsEnd({
    required this.durationHours,
    required this.estimatedDistanceKm,
    required this.actualDistanceKm,
    required this.distanceDifferenceKm,
    required this.estimatedPrice,
    required this.extraCharge,
    required this.finalPrice,
    required this.commission,
    required this.ownerPayout,
  });

  factory TripDetailsEnd.fromJson(Map<String, dynamic> json) {
    return TripDetailsEnd(
      durationHours: (json['duration_hours'] as num).toDouble(),
      estimatedDistanceKm: (json['estimated_distance_km'] as num).toDouble(),
      actualDistanceKm: (json['actual_distance_km'] as num).toDouble(),
      distanceDifferenceKm: (json['distance_difference_km'] as num).toDouble(),
      estimatedPrice: (json['estimated_price'] as num).toDouble(),
      extraCharge: (json['extra_charge'] as num).toDouble(),
      finalPrice: (json['final_price'] as num).toDouble(),
      commission: (json['commission'] as num).toDouble(),
      ownerPayout: (json['owner_payout'] as num).toDouble(),
    );
  }
}

class DistanceAdjustmentEnd {
  final String type;
  final String explanation;
  final double extraChargeApplied;
  final bool chargedImmediately;

  const DistanceAdjustmentEnd({
    required this.type,
    required this.explanation,
    required this.extraChargeApplied,
    required this.chargedImmediately,
  });

  factory DistanceAdjustmentEnd.fromJson(Map<String, dynamic> json) {
    return DistanceAdjustmentEnd(
      type: json['type'] as String,
      explanation: json['explanation'] as String,
      extraChargeApplied: (json['extra_charge_applied'] as num).toDouble(),
      chargedImmediately: json['charged_immediately'] as bool,
    );
  }
}

class EarningsUpdateEnd {
  final double ownerTotalEarnings;
  final double bikeTotalEarnings;
  final double earningsAdded;

  const EarningsUpdateEnd({
    required this.ownerTotalEarnings,
    required this.bikeTotalEarnings,
    required this.earningsAdded,
  });

  factory EarningsUpdateEnd.fromJson(Map<String, dynamic> json) {
    return EarningsUpdateEnd(
      ownerTotalEarnings: (json['owner_total_earnings'] as num).toDouble(),
      bikeTotalEarnings: (json['bike_total_earnings'] as num).toDouble(),
      earningsAdded: (json['earnings_added'] as num).toDouble(),
    );
  }
}

class BikeStatusEnd {
  final bool isAvailable;
  final String status;
  final String name;

  const BikeStatusEnd({
    required this.isAvailable,
    required this.status,
    required this.name,
  });

  factory BikeStatusEnd.fromJson(Map<String, dynamic> json) {
    return BikeStatusEnd(
      isAvailable: json['is_available'] as bool,
      status: json['status'] as String,
      name: json['name'] as String,
    );
  }
}

class EndTripResponse {
  final String message;
  final TripDetailsEnd tripDetails;
  final DistanceAdjustmentEnd distanceAdjustment;
  final EarningsUpdateEnd earningsUpdate;
  final BikeStatusEnd bikeStatus;

  const EndTripResponse({
    required this.message,
    required this.tripDetails,
    required this.distanceAdjustment,
    required this.earningsUpdate,
    required this.bikeStatus,
  });

  factory EndTripResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('message') ||
        !json.containsKey('trip_details') ||
        !json.containsKey('distance_adjustment') ||
        !json.containsKey('earnings_update') ||
        !json.containsKey('bike_status')) {
      throw const FormatException(
        "Invalid JSON for EndTripResponse: Missing one or more required keys.",
      );
    }
    return EndTripResponse(
      message: json['message'] as String,
      tripDetails: TripDetailsEnd.fromJson(
        json['trip_details'] as Map<String, dynamic>,
      ),
      distanceAdjustment: DistanceAdjustmentEnd.fromJson(
        json['distance_adjustment'] as Map<String, dynamic>,
      ),
      earningsUpdate: EarningsUpdateEnd.fromJson(
        json['earnings_update'] as Map<String, dynamic>,
      ),
      bikeStatus: BikeStatusEnd.fromJson(
        json['bike_status'] as Map<String, dynamic>,
      ),
    );
  }
}

// --- Cancel Trip (POST /trip/cancel/{trip_id}/) ---
class CancelTripResponse {
  final String message;

  const CancelTripResponse({required this.message});

  factory CancelTripResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('message')) {
      throw const FormatException(
        "Invalid JSON for CancelTripResponse: Missing 'message'.",
      );
    }
    return CancelTripResponse(message: json['message'] as String);
  }
}

class GetUserTripsResponse {
  final bool success;
  final List<UserTrip> trips;
  final int totalTrips;
  final String user;

  const GetUserTripsResponse({
    required this.success,
    required this.trips,
    required this.totalTrips,
    required this.user,
  });

  factory GetUserTripsResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('success') ||
        !json.containsKey('trips') ||
        !json.containsKey('total_trips') ||
        !json.containsKey('user')) {
      throw const FormatException(
        "Invalid JSON for GetUserTripsResponse: Missing one or more required keys.",
      );
    }
    var tripsList = json['trips'] as List;
    List<UserTrip> tripsData =
        tripsList
            .map((i) => UserTrip.fromJson(i as Map<String, dynamic>))
            .toList();

    return GetUserTripsResponse(
      success: json['success'] as bool,
      trips: tripsData,
      totalTrips: json['total_trips'] as int,
      user: json['user'] as String,
    );
  }
}

class WebSocketNotification {
  final String type; // e.g., "send_notification"
  final String title;
  final String message;
  final Map<String, dynamic>
  data; // This will be parsed further based on title or other clues

  const WebSocketNotification({
    required this.type,
    required this.title,
    required this.message,
    required this.data,
  });

  factory WebSocketNotification.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('type') ||
        !json.containsKey('title') ||
        !json.containsKey('message') ||
        !json.containsKey('data')) {
      throw const FormatException(
        "Invalid JSON for WebSocketNotification: Missing keys.",
      );
    }
    return WebSocketNotification(
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      data: json['data'] as Map<String, dynamic>,
    );
  }
}

// Specific Data Models for different notification types

class BikeLocationData {
  final double latitude;
  final double longitude;
  final String name;
  final int bikeId;

  const BikeLocationData({
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.bikeId,
  });

  factory BikeLocationData.fromJson(Map<String, dynamic> json) {
    return BikeLocationData(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      name: json['name'] as String,
      bikeId: json['bike_id'] as int,
    );
  }
}

class RideAcceptedNotificationData {
  final int tripId;
  final int?
  chatRoomId; // Made nullable as it might not always be present or needed immediately
  final BikeLocationData bikeLocation;
  final String status; // e.g., "accepted"
  final String tripStatus; // e.g., "waiting"
  final String ownerUsername;
  final String? nextStep;
  final String? instructions;

  const RideAcceptedNotificationData({
    required this.tripId,
    this.chatRoomId,
    required this.bikeLocation,
    required this.status,
    required this.tripStatus,
    required this.ownerUsername,
    this.nextStep,
    this.instructions,
  });

  factory RideAcceptedNotificationData.fromJson(Map<String, dynamic> json) {
    return RideAcceptedNotificationData(
      tripId: json['trip_id'] as int,
      chatRoomId: json['chat_room_id'] as int?,
      bikeLocation: BikeLocationData.fromJson(
        json['bike_location'] as Map<String, dynamic>,
      ),
      status: json['status'] as String,
      tripStatus: json['trip_status'] as String,
      ownerUsername: json['owner_username'] as String,
      nextStep: json['next_step'] as String?,
      instructions: json['instructions'] as String?,
    );
  }
}

class RideDeclinedNotificationData {
  final String? requestId; // Corresponds to temp_request_id or similar
  final String? reason;
  final String? bikeName;
  final String? ownerUsername;
  // The Python snippet shows 'rider_notification_data' which is generic.
  // We'll assume it might contain these fields based on context.
  // Add more fields if the actual 'rider_notification_data' structure is more complex.

  const RideDeclinedNotificationData({
    this.requestId,
    this.reason,
    this.bikeName,
    this.ownerUsername,
  });

  factory RideDeclinedNotificationData.fromJson(Map<String, dynamic> json) {
    // Adjust based on actual keys in rider_notification_data for declined rides
    return RideDeclinedNotificationData(
      requestId:
          json['request_id'] as String? ?? json['temp_request_id'] as String?,
      reason:
          json['reason'] as String? ??
          "Ride request was declined.", // Default if not provided
      bikeName: json['bike_name'] as String?,
      ownerUsername: json['owner_username'] as String?,
    );
  }
}

class TripStartedNotificationData {
  final int tripId;
  final String startTime; // ISO 8601 DateTime string

  const TripStartedNotificationData({
    required this.tripId,
    required this.startTime,
  });

  factory TripStartedNotificationData.fromJson(Map<String, dynamic> json) {
    return TripStartedNotificationData(
      tripId: json['trip_id'] as int,
      startTime: json['start_time'] as String,
    );
  }
}

class DistanceAdjustmentData {
  final String type;
  final String explanation;
  final double extraCharge;
  final bool chargedImmediately;

  const DistanceAdjustmentData({
    required this.type,
    required this.explanation,
    required this.extraCharge,
    required this.chargedImmediately,
  });

  factory DistanceAdjustmentData.fromJson(Map<String, dynamic> json) {
    return DistanceAdjustmentData(
      type: json['type'] as String,
      explanation: json['explanation'] as String,
      extraCharge: (json['extra_charge'] as num).toDouble(),
      chargedImmediately: json['charged_immediately'] as bool,
    );
  }
}

class TripCompletedNotificationData {
  final int tripId;
  final double durationHours;
  final double estimatedDistanceKm;
  final double actualDistanceKm;
  final double distanceDifference;
  final double estimatedPrice;
  final double extraCharge;
  final double finalPrice;
  final DistanceAdjustmentData distanceAdjustment;
  final String paymentStatus;
  final String bikeName;

  const TripCompletedNotificationData({
    required this.tripId,
    required this.durationHours,
    required this.estimatedDistanceKm,
    required this.actualDistanceKm,
    required this.distanceDifference,
    required this.estimatedPrice,
    required this.extraCharge,
    required this.finalPrice,
    required this.distanceAdjustment,
    required this.paymentStatus,
    required this.bikeName,
  });

  factory TripCompletedNotificationData.fromJson(Map<String, dynamic> json) {
    return TripCompletedNotificationData(
      tripId: json['trip_id'] as int,
      durationHours: (json['duration_hours'] as num).toDouble(),
      estimatedDistanceKm: (json['estimated_distance_km'] as num).toDouble(),
      actualDistanceKm: (json['actual_distance_km'] as num).toDouble(),
      distanceDifference: (json['distance_difference'] as num).toDouble(),
      estimatedPrice: (json['estimated_price'] as num).toDouble(),
      extraCharge: (json['extra_charge'] as num).toDouble(),
      finalPrice: (json['final_price'] as num).toDouble(),
      distanceAdjustment: DistanceAdjustmentData.fromJson(
        json['distance_adjustment'] as Map<String, dynamic>,
      ),
      paymentStatus: json['payment_status'] as String,
      bikeName: json['bike_name'] as String,
    );
  }
}

class NearbyBike {
  final int id;
  final String bikeName;
  final String brand;
  final String model;
  final LocationPoint location;
  final String? bikeAddress;
  final double distance;
  final int? batteryLevel;
  final String? bikeImage;

  const NearbyBike({
    required this.id,
    required this.bikeName,
    required this.brand,
    required this.model,
    required this.location,
    this.bikeAddress,
    required this.distance,
    this.batteryLevel,
    this.bikeImage,
  });

  factory NearbyBike.fromJson(Map<String, dynamic> json) {
    return NearbyBike(
      id: json['id'] as int,
      bikeName: json['bike_name'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      location: LocationPoint.fromJson(
        json['location'] as Map<String, dynamic>,
      ),
      bikeAddress: json['bike_address'] as String?,
      distance: (json['distance'] as num).toDouble(),
      batteryLevel: json['battery_level'] as int?,
      bikeImage: json['bike_image'] as String?,
    );
  }
}

class RideRequestInitialResponse {
  final String message;
  final String tempRequestId;

  const RideRequestInitialResponse({
    required this.message,
    required this.tempRequestId,
  });

  factory RideRequestInitialResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('message') || !json.containsKey('temp_request_id')) {
      throw const FormatException(
        "Invalid JSON for RideRequestInitialResponse: Missing keys.",
      );
    }
    return RideRequestInitialResponse(
      message: json['message'] as String,
      tempRequestId: json['temp_request_id'] as String,
    );
  }
}

class BikeStatusCancel {
  final String name;
  final String status;
  final String note;

  const BikeStatusCancel({
    required this.name,
    required this.status,
    required this.note,
  });

  factory BikeStatusCancel.fromJson(Map<String, dynamic> json) {
    return BikeStatusCancel(
      name: json['name'] as String,
      status: json['status'] as String,
      note: json['note'] as String,
    );
  }
}

class CancelledRequestDetails {
  final String bikeName;
  final String ownerUsername;
  final String cancelledAt;

  const CancelledRequestDetails({
    required this.bikeName,
    required this.ownerUsername,
    required this.cancelledAt,
  });

  factory CancelledRequestDetails.fromJson(Map<String, dynamic> json) {
    return CancelledRequestDetails(
      bikeName: json['bike_name'] as String,
      ownerUsername: json['owner_username'] as String,
      cancelledAt: json['cancelled_at'] as String,
    );
  }
}

class CancelRideRequestResponse {
  final bool success;
  final String message;
  final CancelledRequestDetails cancelledRequest;
  final BikeStatusCancel bikeStatus;
  final bool ownerNotified;
  final String nextStep;

  const CancelRideRequestResponse({
    required this.success,
    required this.message,
    required this.cancelledRequest,
    required this.bikeStatus,
    required this.ownerNotified,
    required this.nextStep,
  });

  factory CancelRideRequestResponse.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('success') ||
        !json.containsKey('message') ||
        !json.containsKey('details')) {
      throw const FormatException(
        "Invalid JSON for CancelRideRequestResponse: Missing required keys.",
      );
    }

    final details = json['details'] as Map<String, dynamic>;

    if (!details.containsKey('cancelled_request') ||
        !details.containsKey('bike_status') ||
        !details.containsKey('owner_notified') ||
        !details.containsKey('next_step')) {
      throw const FormatException(
        "Invalid JSON for CancelRideRequestResponse: Missing details keys.",
      );
    }

    return CancelRideRequestResponse(
      success: json['success'] as bool,
      message: json['message'] as String,
      cancelledRequest: CancelledRequestDetails.fromJson(
        details['cancelled_request'] as Map<String, dynamic>,
      ),
      bikeStatus: BikeStatusCancel.fromJson(
        details['bike_status'] as Map<String, dynamic>,
      ),
      ownerNotified: details['owner_notified'] as bool,
      nextStep: details['next_step'] as String,
    );
  }
}

typedef NearbyBikesResponse = List<NearbyBike>;

// Helper function to parse a list of NearbyBike
List<NearbyBike> parseNearbyBikes(String responseBody) {
  final parsed = jsonDecode(responseBody).cast<Map<String, dynamic>>();
  return parsed.map<NearbyBike>((json) => NearbyBike.fromJson(json)).toList();
}

// --- Active Trip (GET /trip/active/) ---

class ActiveTripBike {
  final int id;
  final String name;
  final String brand;
  final String model;
  final double? latitude;
  final double? longitude;
  final String? bikeImage;

  const ActiveTripBike({
    required this.id,
    required this.name,
    required this.brand,
    required this.model,
    this.latitude,
    this.longitude,
    this.bikeImage,
  });

  factory ActiveTripBike.fromJson(Map<String, dynamic> json) {
    return ActiveTripBike(
      id: json['id'] as int,
      name: json['name'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      bikeImage: json['bike_image'] as String?,
    );
  }
}

class ActiveTripOwner {
  final int id;
  final String username;

  const ActiveTripOwner({required this.id, required this.username});

  factory ActiveTripOwner.fromJson(Map<String, dynamic> json) {
    return ActiveTripOwner(
      id: json['id'] as int,
      username: json['username'] as String,
    );
  }
}

class ActiveTripLocation {
  final double? latitude;
  final double? longitude;
  final String? address;

  const ActiveTripLocation({this.latitude, this.longitude, this.address});

  factory ActiveTripLocation.fromJson(Map<String, dynamic> json) {
    return ActiveTripLocation(
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      address: json['address'] as String?,
    );
  }
}

class ActiveTrip {
  final int id;
  final String status;
  final String tripDate;
  final String? startTime;
  final ActiveTripBike? bike;
  final ActiveTripOwner? owner;
  final ActiveTripLocation origin;
  final ActiveTripLocation destination;
  final double? price;
  final double? distance;
  final String? paymentStatus;
  final String? paymentIntentId;
  final int? chatRoomId;

  const ActiveTrip({
    required this.id,
    required this.status,
    required this.tripDate,
    this.startTime,
    this.bike,
    this.owner,
    required this.origin,
    required this.destination,
    this.price,
    this.distance,
    this.paymentStatus,
    this.paymentIntentId,
    this.chatRoomId,
  });

  factory ActiveTrip.fromJson(Map<String, dynamic> json) {
    return ActiveTrip(
      id: json['id'] as int,
      status: json['status'] as String,
      tripDate: json['trip_date'] as String,
      startTime: json['start_time'] as String?,
      bike: json['bike'] != null
          ? ActiveTripBike.fromJson(json['bike'] as Map<String, dynamic>)
          : null,
      owner: json['owner'] != null
          ? ActiveTripOwner.fromJson(json['owner'] as Map<String, dynamic>)
          : null,
      origin: ActiveTripLocation.fromJson(json['origin'] as Map<String, dynamic>),
      destination: ActiveTripLocation.fromJson(
          json['destination'] as Map<String, dynamic>),
      price: (json['price'] as num?)?.toDouble(),
      distance: (json['distance'] as num?)?.toDouble(),
      paymentStatus: json['payment_status'] as String?,
      paymentIntentId: json['payment_intent_id'] as String?,
      chatRoomId: json['chat_room_id'] as int?,
    );
  }
}

class ActiveTripResponse {
  final ActiveTrip? activeTrip;

  const ActiveTripResponse({this.activeTrip});

  factory ActiveTripResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['active_trip'];
    return ActiveTripResponse(
      activeTrip:
          raw != null ? ActiveTrip.fromJson(raw as Map<String, dynamic>) : null,
    );
  }
}

// --- Request Status (GET /riderequest/status/<temp_request_id>/) ---

class RequestStatusResponse {
  final String status;
  final String tempRequestId;
  final String? bikeName;
  final int? ownerId;
  final double? price;
  final String? requestedTime;

  const RequestStatusResponse({
    required this.status,
    required this.tempRequestId,
    this.bikeName,
    this.ownerId,
    this.price,
    this.requestedTime,
  });

  factory RequestStatusResponse.fromJson(Map<String, dynamic> json) {
    return RequestStatusResponse(
      status: json['status'] as String,
      tempRequestId: json['temp_request_id'] as String,
      bikeName: json['bike_name'] as String?,
      ownerId: json['owner_id'] as int?,
      price: (json['price'] as num?)?.toDouble(),
      requestedTime: json['requested_time'] as String?,
    );
  }
}

// --- Request Ride With Payment (POST /riderequest/request-with-payment/) ---

class RideRequestWithPaymentRequest {
  final double pickupLatitude;
  final double pickupLongitude;
  final double destinationLatitude;
  final double destinationLongitude;
  final String priceToken;
  final String destinationAddress;
  final String originAddress;
  final String paymentType;

  const RideRequestWithPaymentRequest({
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.priceToken,
    required this.destinationAddress,
    required this.originAddress,
    this.paymentType = 'card',
  });

  Map<String, dynamic> toJson() => {
        'pickup_latitude': pickupLatitude,
        'pickup_longitude': pickupLongitude,
        'destination_latitude': destinationLatitude,
        'destination_longitude': destinationLongitude,
        'price_token': priceToken,
        'destination_address': destinationAddress,
        'origin_address': originAddress,
        'payment_type': paymentType,
      };
}

class PaymentDetails {
  final String clientSecret;
  final String paymentIntentId;
  final String customerId;
  final String totalAmount;
  final String ownerEarnings;
  final String platformCommission;

  const PaymentDetails({
    required this.clientSecret,
    required this.paymentIntentId,
    required this.customerId,
    required this.totalAmount,
    required this.ownerEarnings,
    required this.platformCommission,
  });

  factory PaymentDetails.fromJson(Map<String, dynamic> json) {
    return PaymentDetails(
      clientSecret: json['client_secret'] as String,
      paymentIntentId: json['payment_intent_id'] as String,
      customerId: json['customer_id'] as String,
      totalAmount: json['total_amount'] as String,
      ownerEarnings: json['owner_earnings'] as String,
      platformCommission: json['platform_commission'] as String,
    );
  }
}

class RequestRideWithPaymentResponse {
  final bool success;
  final String tempRequestId;
  final PaymentDetails payment;
  final String message;
  final String? expiresAt;

  const RequestRideWithPaymentResponse({
    required this.success,
    required this.tempRequestId,
    required this.payment,
    required this.message,
    this.expiresAt,
  });

  factory RequestRideWithPaymentResponse.fromJson(Map<String, dynamic> json) {
    return RequestRideWithPaymentResponse(
      success: json['success'] as bool? ?? true,
      tempRequestId: json['temp_request_id'] as String,
      payment: PaymentDetails.fromJson(json['payment'] as Map<String, dynamic>),
      message: json['message'] as String,
      expiresAt: json['expires_at'] as String?,
    );
  }
}

// --- Begin Trip (POST /trip/begin/<trip_id>/) ---

class BeginTripResponse {
  final String message;
  final String status;

  const BeginTripResponse({required this.message, required this.status});

  factory BeginTripResponse.fromJson(Map<String, dynamic> json) {
    return BeginTripResponse(
      message: json['message'] as String,
      status: json['status'] as String,
    );
  }
}

// --- Rate Trip (POST /trip/<trip_id>/rate/) ---

class RateTripRequest {
  final int rating;
  final String? review;

  const RateTripRequest({required this.rating, this.review});

  Map<String, dynamic> toJson() => {
        'rating': rating,
        if (review != null) 'review': review,
      };
}

class RateTripResponse {
  final bool success;
  final int rating;
  final String? review;
  final double? bikeNewRating;

  const RateTripResponse({
    required this.success,
    required this.rating,
    this.review,
    this.bikeNewRating,
  });

  factory RateTripResponse.fromJson(Map<String, dynamic> json) {
    return RateTripResponse(
      success: json['success'] as bool,
      rating: json['rating'] as int,
      review: json['review'] as String?,
      bikeNewRating: (json['bike_new_rating'] as num?)?.toDouble(),
    );
  }
}
