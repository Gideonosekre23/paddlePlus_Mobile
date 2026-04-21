import 'package:flutter/material.dart';

class OwnerTripsResponse {
  final bool success;
  final List<OwnerTrip> trips;
  final int totalTrips;
  final OwnerInfo owner;

  OwnerTripsResponse({
    required this.success,
    required this.trips,
    required this.totalTrips,
    required this.owner,
  });

  factory OwnerTripsResponse.fromJson(Map<String, dynamic> json) {
    return OwnerTripsResponse(
      success: json['success'] ?? false,
      trips:
          (json['trips'] as List<dynamic>?)
              ?.map((trip) => OwnerTrip.fromJson(trip))
              .toList() ??
          [],
      totalTrips: json['total_trips'] ?? 0,
      owner: OwnerInfo.fromJson(json['owner'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'trips': trips.map((trip) => trip.toJson()).toList(),
      'total_trips': totalTrips,
      'owner': owner.toJson(),
    };
  }
}

/// Individual owner trip model
class OwnerTrip {
  final int id;
  final String bikeName;
  final BikeInfo? bikeInfo;
  final TripLocation startLocation;
  final TripLocation endLocation;
  final DateTime? date;
  final String status;
  final double? price;
  final double? ownerPayout;
  final double? distance;
  final String? paymentStatus;
  final RenterInfo? renter;

  OwnerTrip({
    required this.id,
    required this.bikeName,
    this.bikeInfo,
    required this.startLocation,
    required this.endLocation,
    this.date,
    required this.status,
    this.price,
    this.ownerPayout,
    this.distance,
    this.paymentStatus,
    this.renter,
  });

  factory OwnerTrip.fromJson(Map<String, dynamic> json) {
    return OwnerTrip(
      id: json['id'] ?? 0,
      bikeName: json['bike_name'] ?? 'Unknown Bike',
      bikeInfo: json['bike_info'] != null
          ? BikeInfo.fromJson(json['bike_info'])
          : null,
      startLocation: TripLocation.fromJson(json['start_location'] ?? {}),
      endLocation: TripLocation.fromJson(json['end_location'] ?? {}),
      date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
      status: json['status'] ?? 'unknown',
      price: json['price']?.toDouble(),
      ownerPayout: json['owner_payout']?.toDouble(),
      distance: json['distance']?.toDouble(),
      paymentStatus: json['payment_status'],
      renter: json['renter'] != null
          ? RenterInfo.fromJson(json['renter'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bike_name': bikeName,
      'bike_info': bikeInfo?.toJson(),
      'start_location': startLocation.toJson(),
      'end_location': endLocation.toJson(),
      'date': date?.toIso8601String(),
      'status': status,
      'price': price,
      'owner_payout': ownerPayout,
      'distance': distance,
      'payment_status': paymentStatus,
      'renter': renter?.toJson(),
    };
  }

  // Helper getters for UI
  String get formattedEarnings {
    if (ownerPayout != null) {
      return '${ownerPayout!.toStringAsFixed(2)} RON';
    }
    return '0.00 RON';
  }

  String get formattedDistance {
    if (distance != null) {
      return '${distance!.toStringAsFixed(1)} km';
    }
    return '0.0 km';
  }

  String get formattedDate {
    if (date != null) {
      return '${date!.day}/${date!.month}/${date!.year}';
    }
    return 'Unknown Date';
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'canceled':
      case 'cancelled':
        return Colors.red;
      case 'waiting':
        return Colors.orange;
      case 'started':
      case 'ontrip':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String get statusDisplayText {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'canceled':
      case 'cancelled':
        return 'Cancelled';
      case 'waiting':
        return 'Waiting';
      case 'started':
        return 'Started';
      case 'ontrip':
        return 'On Trip';
      default:
        return status.toUpperCase();
    }
  }
}

/// Bike information model
class BikeInfo {
  final int? id;
  final String brand;
  final String model;
  final String color;

  BikeInfo({
    this.id,
    required this.brand,
    required this.model,
    required this.color,
  });

  factory BikeInfo.fromJson(Map<String, dynamic> json) {
    return BikeInfo(
      id: json['id'],
      brand: json['brand'] ?? 'Unknown',
      model: json['model'] ?? 'Unknown',
      color: json['color'] ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'brand': brand, 'model': model, 'color': color};
  }

  String get displayName => '$brand $model';
}

/// Trip location model
class TripLocation {
  final String address;
  final double? latitude;
  final double? longitude;

  TripLocation({required this.address, this.latitude, this.longitude});

  factory TripLocation.fromJson(Map<String, dynamic> json) {
    return TripLocation(
      address: json['address'] ?? 'Unknown Location',
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'address': address, 'latitude': latitude, 'longitude': longitude};
  }

  // Helper getter for display
  String get shortAddress {
    // Get first part of address (before first comma)
    if (address.contains(',')) {
      return address.split(',').first.trim();
    }
    return address;
  }
}

/// Renter information model
class RenterInfo {
  final String username;
  final int id;
  final String? phone;

  RenterInfo({required this.username, required this.id, this.phone});

  factory RenterInfo.fromJson(Map<String, dynamic> json) {
    return RenterInfo(
      username: json['username'] ?? 'Unknown User',
      id: json['id'] ?? 0,
      phone: json['phone'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'username': username, 'id': id, 'phone': phone};
  }
}

/// Owner information model
class OwnerInfo {
  final String username;
  final int id;
  final double totalEarnings;
  final String verificationStatus;

  OwnerInfo({
    required this.username,
    required this.id,
    required this.totalEarnings,
    required this.verificationStatus,
  });

  factory OwnerInfo.fromJson(Map<String, dynamic> json) {
    return OwnerInfo(
      username: json['username'] ?? 'Unknown',
      id: json['id'] ?? 0,
      totalEarnings: json['total_earnings']?.toDouble() ?? 0.0,
      verificationStatus: json['verification_status'] ?? 'unverified',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'id': id,
      'total_earnings': totalEarnings,
      'verification_status': verificationStatus,
    };
  }

  // Helper getters
  String get formattedTotalEarnings {
    return '${totalEarnings.toStringAsFixed(2)} RON';
  }

  bool get isVerified => verificationStatus.toLowerCase() == 'verified';

  Color get verificationStatusColor {
    switch (verificationStatus.toLowerCase()) {
      case 'verified':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }
}
