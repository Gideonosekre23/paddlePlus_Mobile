class Bike {
  final int id;
  final String bikeName;
  final String brand;
  final String model;
  final String? color;
  final String? size;
  final int? year;
  final String? description;
  final BikeLocation location;
  final String? bikeAddress;
  final bool isAvailable;
  final String? bikeImage;
  final bool isActive;
  final String bikeStatus;
  final String? hardwareStatus;
  final int? batteryLevel;
  final String? ownerUsername;
  final HardwareStatus? hardware;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Bike({
    required this.id,
    required this.bikeName,
    required this.brand,
    required this.model,
    this.color,
    this.size,
    this.year,
    this.description,
    required this.location,
    this.bikeAddress,
    this.bikeImage,
    required this.isAvailable,
    required this.isActive,
    required this.bikeStatus,
    this.hardwareStatus,
    this.batteryLevel,
    this.ownerUsername,
    this.hardware,
    this.createdAt,
    this.updatedAt,
  });

  bool get needsActivation => !isActive;
  bool get canBeToggled => isActive;
  bool get isReadyForRiders =>
      isActive && isAvailable && bikeStatus == 'available';

  factory Bike.fromJson(Map<String, dynamic> json) {
    return Bike(
      id: json['id'],
      bikeName: json['bike_name'],
      brand: json['brand'],
      model: json['model'],
      color: json['color'],
      size: json['size'],
      year: json['year'],
      description: json['description'],
      bikeImage: json['bike_image'],
      location: BikeLocation.fromJson(
        json['current_location'] ??
            {'latitude': json['latitude'], 'longitude': json['longitude']},
      ),
      bikeAddress: json['bike_address'],
      isAvailable: json['is_available'] ?? false,
      isActive: json['is_active'] ?? false,
      bikeStatus: json['bike_status'] ?? 'inactive',
      hardwareStatus: json['hardware_status'],
      batteryLevel: json['battery_level'],
      ownerUsername: json['owner_username'],
      hardware: json['hardware_info'] != null
          ? HardwareStatus.fromJson(json['hardware_info'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bike_name': bikeName,
      'brand': brand,
      'model': model,
      'color': color,
      'size': size,
      'year': year,
      'description': description,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'bike_address': bikeAddress,
      'is_available': isAvailable,
      'bike_image': bikeImage,
      'is_active': isActive,
      'bike_status': bikeStatus,
      'hardware_status': hardwareStatus,
      'battery_level': batteryLevel,
      'owner_username': ownerUsername,
      'hardware_info': hardware?.toJson(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class BikeLocation {
  final double latitude;
  final double longitude;

  BikeLocation({required this.latitude, required this.longitude});

  factory BikeLocation.fromJson(Map<String, dynamic> json) {
    return BikeLocation(
      latitude: (json['latitude'] is num)
          ? json['latitude'].toDouble()
          : double.parse(json['latitude'].toString()),
      longitude: (json['longitude'] is num)
          ? json['longitude'].toDouble()
          : double.parse(json['longitude'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {'latitude': latitude, 'longitude': longitude};
  }
}

class HardwareStatus {
  final bool isAssigned;
  final int? batteryLevel;
  final String? serialNumber;
  final String status;
  final bool isOnline;
  final int? signalStrength;
  final String? firmwareVersion;
  final DateTime? lastPing;
  final DateTime? assignedAt;

  HardwareStatus({
    required this.isAssigned,
    this.batteryLevel,
    this.serialNumber,
    required this.status,
    required this.isOnline,
    this.signalStrength,
    this.firmwareVersion,
    this.lastPing,
    this.assignedAt,
  });

  factory HardwareStatus.fromJson(Map<String, dynamic> json) {
    return HardwareStatus(
      isAssigned: json['is_assigned'] ?? false,
      batteryLevel: json['battery_level'],
      serialNumber: json['serial_number'],
      status: json['status'] ?? 'unassigned',
      isOnline: json['is_online'] ?? false,
      signalStrength: json['signal_strength'],
      firmwareVersion: json['firmware_version'],
      lastPing: json['last_ping'] != null
          ? DateTime.parse(json['last_ping'])
          : null,
      assignedAt: json['assigned_at'] != null
          ? DateTime.parse(json['assigned_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_assigned': isAssigned,
      'battery_level': batteryLevel,
      'serial_number': serialNumber,
      'status': status,
      'is_online': isOnline,
      'signal_strength': signalStrength,
      'firmware_version': firmwareVersion,
      'last_ping': lastPing?.toIso8601String(),
      'assigned_at': assignedAt?.toIso8601String(),
    };
  }
}

class AddBikeRequest {
  final String bikeName;
  final String brand;
  final String model;
  final String? color;
  final String? size;
  final int? year;
  final double latitude;
  final double longitude;
  final String? bikeAddress;
  final String? description;
  final String? bikeImage;

  AddBikeRequest({
    required this.bikeName,
    required this.brand,
    required this.model,
    this.color,
    this.size,
    this.year,
    required this.latitude,
    required this.longitude,
    this.bikeAddress,
    this.description,
    this.bikeImage,
  });

  Map<String, dynamic> toJson() {
    return {
      'bike_name': bikeName,
      'brand': brand,
      'model': model,
      'color': color,
      'size': size,
      'year': year,
      'latitude': latitude,
      'longitude': longitude,
      'bike_address': bikeAddress,
      'description': description,
      if (bikeImage != null) 'bike_image': bikeImage,
    };
  }
}

class ActivateBikeRequest {
  final String serialNumber;

  ActivateBikeRequest({required this.serialNumber});

  Map<String, dynamic> toJson() {
    return {'serial_number': serialNumber};
  }
}

class AddBikeResponse {
  final Bike bike;
  final String message;

  AddBikeResponse({required this.bike, required this.message});

  factory AddBikeResponse.fromJson(Map<String, dynamic> json) {
    return AddBikeResponse(
      bike: Bike.fromJson(json),
      message:
          'Bike added successfully. Please activate it with hardware to make it available.',
    );
  }

  bool get needsActivation => bike.needsActivation;
}

class GetOwnerBikesResponse {
  final List<Bike> bikes;
  final int count;
  final BikesSummary summary;

  GetOwnerBikesResponse({
    required this.bikes,
    required this.count,
    required this.summary,
  });

  factory GetOwnerBikesResponse.fromJson(List<dynamic> json) {
    final bikes = json.map((item) => Bike.fromJson(item)).toList();
    return GetOwnerBikesResponse(
      bikes: bikes,
      count: bikes.length,
      summary: BikesSummary.fromBikes(bikes),
    );
  }
}

class BikesSummary {
  final int totalBikes;
  final int activeBikes;
  final int inactiveBikes;
  final int availableBikes;
  final int needingActivation;

  BikesSummary({
    required this.totalBikes,
    required this.activeBikes,
    required this.inactiveBikes,
    required this.availableBikes,
    required this.needingActivation,
  });

  factory BikesSummary.fromBikes(List<Bike> bikes) {
    return BikesSummary(
      totalBikes: bikes.length,
      activeBikes: bikes.where((b) => b.isActive).length,
      inactiveBikes: bikes.where((b) => !b.isActive).length,
      availableBikes: bikes.where((b) => b.isReadyForRiders).length,
      needingActivation: bikes.where((b) => b.needsActivation).length,
    );
  }
}

class ActivateBikeResponse {
  final String message;
  final HardwareStatus hardwareStatus;
  final int bikeId;
  final bool isNowActive;

  ActivateBikeResponse({
    required this.message,
    required this.hardwareStatus,
    required this.bikeId,
    required this.isNowActive,
  });

  factory ActivateBikeResponse.fromJson(Map<String, dynamic> json) {
    return ActivateBikeResponse(
      message: json['message'],
      hardwareStatus: HardwareStatus.fromJson(json['hardware_status']),
      bikeId: json['bike_id'] ?? 0,
      isNowActive: true,
    );
  }
}

class ToggleBikeResponse {
  final String message;
  final bool isAvailable;
  final String bikeStatus;
  final int bikeId;
  final bool canBeUsedByRiders;

  ToggleBikeResponse({
    required this.message,
    required this.isAvailable,
    required this.bikeStatus,
    required this.bikeId,
    required this.canBeUsedByRiders,
  });

  factory ToggleBikeResponse.fromJson(Map<String, dynamic> json) {
    final isAvailable = json['is_available'] ?? false;
    final bikeStatus = json['bike_status'] ?? 'disabled';

    return ToggleBikeResponse(
      message: json['message'],
      isAvailable: isAvailable,
      bikeStatus: bikeStatus,
      bikeId: json['bike_id'] ?? 0,
      canBeUsedByRiders: isAvailable && bikeStatus == 'available',
    );
  }
}

class RemoveBikeResponse {
  final String message;
  final int bikeId;
  final bool hardwareUnassigned;

  RemoveBikeResponse({
    required this.message,
    required this.bikeId,
    required this.hardwareUnassigned,
  });

  factory RemoveBikeResponse.fromJson(Map<String, dynamic> json) {
    return RemoveBikeResponse(
      message: json['message'],
      bikeId: json['bike_id'],
      hardwareUnassigned: true,
    );
  }
}
