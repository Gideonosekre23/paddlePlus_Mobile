// Trip
class Trip {
  final int id;
  final String bikeName;
  final Map<String, dynamic> bikeInfo;
  final Map<String, dynamic> ownerInfo;
  final Map<String, dynamic> startLocation;
  final Map<String, dynamic> endLocation;
  final DateTime? date;
  final String status;
  final double? price;
  final double? distance;
  final String paymentStatus;
  final DateTime? createdAt;

  const Trip({
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
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as int,
    bikeName: json['bike_name'] as String,
    bikeInfo: json['bike_info'] as Map<String, dynamic>,
    ownerInfo: json['owner_info'] as Map<String, dynamic>,
    startLocation: json['start_location'] as Map<String, dynamic>,
    endLocation: json['end_location'] as Map<String, dynamic>,
    date: json['date'] != null ? DateTime.parse(json['date'] as String) : null,
    status: json['status'] as String,
    price: json['price'] != null ? (json['price'] as num).toDouble() : null,
    distance:
        json['distance'] != null ? (json['distance'] as num).toDouble() : null,
    paymentStatus: json['payment_status'] as String,
    createdAt:
        json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
  );

  bool get isWaiting => status == 'waiting';
  bool get isStarted => status == 'started';
  bool get isCompleted => status == 'completed';
  bool get isCanceled => status == 'canceled';

  String get formattedPrice =>
      price != null ? '€${price!.toStringAsFixed(2)}' : 'N/A';
  String get formattedDistance =>
      distance != null ? '${distance!.toStringAsFixed(2)} km' : 'N/A';
}

// Start Trip Response
class StartTripResponse {
  final String message;
  final DateTime startTime;

  const StartTripResponse({required this.message, required this.startTime});

  factory StartTripResponse.fromJson(Map<String, dynamic> json) =>
      StartTripResponse(
        message: json['message'] as String,
        startTime: DateTime.parse(json['start_time'] as String),
      );
}

// End Trip Response
class EndTripResponse {
  final String message;
  final Map<String, dynamic> tripDetails;
  final Map<String, dynamic> distanceAdjustment;
  final Map<String, dynamic> earningsUpdate;
  final Map<String, dynamic> bikeStatus;

  const EndTripResponse({
    required this.message,
    required this.tripDetails,
    required this.distanceAdjustment,
    required this.earningsUpdate,
    required this.bikeStatus,
  });

  factory EndTripResponse.fromJson(Map<String, dynamic> json) =>
      EndTripResponse(
        message: json['message'] as String,
        tripDetails: json['trip_details'] as Map<String, dynamic>,
        distanceAdjustment: json['distance_adjustment'] as Map<String, dynamic>,
        earningsUpdate: json['earnings_update'] as Map<String, dynamic>,
        bikeStatus: json['bike_status'] as Map<String, dynamic>,
      );

  double get durationHours => (tripDetails['duration_hours'] as num).toDouble();
  double get estimatedDistance =>
      (tripDetails['estimated_distance_km'] as num).toDouble();
  double get actualDistance =>
      (tripDetails['actual_distance_km'] as num).toDouble();
  double get finalPrice => (tripDetails['final_price'] as num).toDouble();
  double get extraCharge => (tripDetails['extra_charge'] as num).toDouble();

  String get formattedDuration => '${durationHours.toStringAsFixed(1)} hours';
  String get formattedFinalPrice => '€${finalPrice.toStringAsFixed(2)}';
  bool get hasExtraCharge => extraCharge > 0;
}

// User Trips Response
class UserTripsResponse {
  final bool success;
  final List<Trip> trips;
  final int totalTrips;
  final String user;

  const UserTripsResponse({
    required this.success,
    required this.trips,
    required this.totalTrips,
    required this.user,
  });

  factory UserTripsResponse.fromJson(Map<String, dynamic> json) {
    final tripsJson = json['trips'] as List<dynamic>;
    final trips =
        tripsJson
            .map((tripJson) => Trip.fromJson(tripJson as Map<String, dynamic>))
            .toList();

    return UserTripsResponse(
      success: json['success'] as bool,
      trips: trips,
      totalTrips: json['total_trips'] as int,
      user: json['user'] as String,
    );
  }
}
