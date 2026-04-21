import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'package:paddleapp/Apiendpoints/apiservices/Ride_api_service.dart';
import 'package:paddleapp/Apiendpoints/apiservices/auth_api_service.dart';
import 'package:paddleapp/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddleapp/Apiendpoints/models/Ride_models.dart';
import 'package:paddleapp/Apiendpoints/models/auth_models.dart';
import 'package:paddleapp/Apiendpoints/models/api_response.dart';
import 'package:paddleapp/constants/Searcharea.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:paddleapp/consts.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:cached_network_image/cached_network_image.dart';

class Map_page extends StatefulWidget {
  final String? initialDestination;
  final double? initialDestinationLat;
  final double? initialDestinationLng;
  final Function(bool, Map<String, dynamic>?)? onTripStatusChanged;

  const Map_page({
    super.key,
    this.initialDestination,
    this.initialDestinationLat,
    this.initialDestinationLng,
    this.onTripStatusChanged,
  });

  @override
  State<Map_page> createState() => _Map_pageState();
}

class _Map_pageState extends State<Map_page> {
  Location locationController = Location();
  final Completer<GoogleMapController> mapController =
      Completer<GoogleMapController>();
  final TextEditingController _searchController = TextEditingController();
  final UserSessionManager _sessionManager = UserSessionManager();

  Key _searchKey = UniqueKey();
  LatLng? currentposition;
  LatLng? destinationposition;
  LatLng? Bikelocation;
  LatLng? finalDestination;
  double? estimatedPrice;
  bool isActiveTrip = false;
  bool rideAccepted = false;
  bool navigatingToBike = false;
  bool atBikeLocation = false;
  Set<Polyline> polylines = {};
  Set<Marker> markers = {};
  Map<String, dynamic>? selectedBike;
  Map<String, dynamic>? acceptedRideData;
  bool showBikeDetails = false;
  String? tripId;
  String? activeTripId;
  String? bikeOwnerName;
  int? bikeOwnerId;
  String? chatRoomId;

  bool atDestination = false;
  bool _isGettingPolyline = false;
  LatLng? _lastOrigin;
  LatLng? _lastDestination;
  bool _isEstimatingPrice = false;
  String? _priceEstimationError;
  String? _priceToken;
  List<NearbyBike> _fetchedNearbyBikes = [];
  bool _isLoadingBikes = false;

  String? _nearbyBikesError;
  NearbyBike? selectedApiBike;
  bool _isRequestingRide = false;
  String? _rideRequestError;
  String? _tempRequestId;
  Timer? _rideRequestTimeoutTimer;
  String _requestStatus = 'idle';
  StreamSubscription? _wsSubscription;

  // Trip lifecycle: started → waiting for unlock confirmation → ontrip
  bool _tripStarted = false;
  bool _isBeginningTrip = false;

  // Bike conflict: preferred bike taken, alternative offered
  AlternativeBike? _alternativeBike;
  String? _newPriceToken;

  @override
  void initState() {
    super.initState();
    print('🗺️ Google API key: "${google_api_key}" (length: ${google_api_key.length})');
    _setupWebSocketListener();

    _getCurrentLocation().then((_) {
      if (mounted && currentposition != null) {
        _tryRecoverActiveTrip();
        _fetchAndDisplayNearbyBikes();
      }

      if (widget.initialDestination != null &&
          widget.initialDestinationLat != null &&
          widget.initialDestinationLng != null) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _searchController.text = widget.initialDestination!;
            _onDestinationSelected(
              LatLng(
                widget.initialDestinationLat!,
                widget.initialDestinationLng!,
              ),
            );
          }
        });
      }
    });
  }

  void _setupWebSocketListener() {
    _wsSubscription = _sessionManager.wsMessageStream.listen((message) {
      _handleWebSocketMessage(message);
    });
  }

  Future<void> _tryRecoverActiveTrip() async {
    final response = await RideApiService.getActiveTrip();
    if (!mounted) return;
    if (response.success && response.data?.activeTrip != null) {
      final trip = response.data!.activeTrip!;
      setState(() {
        activeTripId = trip.id.toString();
        chatRoomId = trip.chatRoomId?.toString();
        bikeOwnerName = trip.owner?.username;
        if (trip.status == 'started') {
          _tripStarted = true;
          isActiveTrip = false;
        } else if (trip.status == 'ontrip' || trip.status == 'waiting') {
          isActiveTrip = trip.status != 'waiting';
        }
        if (trip.destination.latitude != null &&
            trip.destination.longitude != null) {
          finalDestination = LatLng(
            trip.destination.latitude!,
            trip.destination.longitude!,
          );
          destinationposition = finalDestination;
        }
      });
      if (widget.onTripStatusChanged != null) {
        widget.onTripStatusChanged!(true, {
          'tripId': activeTripId,
          'bikeOwnerName': bikeOwnerName,
          'chatRoomId': chatRoomId,
        });
      }
      _showSuccessSnackbar('Active trip restored. Status: ${trip.status}');
    }
  }

  void _handleWebSocketMessage(Map<String, dynamic> message) {
    final String? messageType = message['type'];
    final dynamic messageData = message['data'];
    print("Map_page: Received WebSocket message: $messageType");

    switch (messageType) {
      case 'notification':
        _handleNotificationMessage(message);
        break;
      case 'ride_request_accepted':
        _handleRideRequestAccepted(messageData);
        break;
      case 'ride_request_declined':
        _handleRideRequestDeclined(messageData);
        break;
      case 'ride_request_timeout':
        _handleRideRequestTimeout(messageData);
        break;
      default:
        print("Map_page: Unhandled message type: $messageType");
    }
  }

  void _handleNotificationMessage(Map<String, dynamic> message) {
    final data = message['data'];
    final String? title = message['title'];

    if (data != null && data['status'] == 'accepted') {
      print("Map_page: Ride accepted notification! Processing...");

      // Extract and transform the data for _handleRideAccepted
      final rideData = {
        'trip_id': data['trip_id'],
        'bike': {
          'latitude': data['bike_location']['latitude'],
          'longitude': data['bike_location']['longitude'],
          'name': data['bike_location']['name'],
          'bike_id': data['bike_location']['bike_id'],
        },
        'destination': {
          'latitude': destinationposition?.latitude,
          'longitude': destinationposition?.longitude,
        },
        'payment': {'amount': estimatedPrice ?? 0.0},
        'owner_username': data['owner_username'],
        'chat_room_id': data['chat_room_id'],
      };

      _handleRideRequestAccepted(rideData);
    } else if (data != null && data['status'] == 'declined') {
      print("Map_page: Ride declined notification! Processing...");
      _handleRideRequestDeclined(data);
    } else {
      print("Map_page: Notification received: $title");
    }
  }

  void _handleRideRequestAccepted(dynamic data) {
    if (!mounted) return;

    print("Map_page: Ride request accepted! Data: $data");

    setState(() {
      _isRequestingRide = false;
      _requestStatus = 'accepted';
      _tempRequestId = null;
    });

    _rideRequestTimeoutTimer?.cancel();
    _handleRideAccepted(data);
  }

  void _handleRideRequestDeclined(dynamic data) {
    if (!mounted) return;

    print("Map_page: Ride request declined: $data");

    setState(() {
      _isRequestingRide = false;
      _requestStatus = 'declined';
      _rideRequestError =
          data['message'] ?? 'The bike owner declined your request.';
      _tempRequestId = null;
    });

    _rideRequestTimeoutTimer?.cancel();

    _showDeclinedMessage(data);

    _searchController.clear();
    _searchKey = UniqueKey();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _resetToIdle();
      }
    });
  }

  void _showDeclinedMessage(dynamic data) {
    final ownerName = data['owner_name'] ?? 'The bike owner';
    final bikeName = data['bike_name'] ?? 'the bike';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '❌ Request Declined',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('$ownerName declined your request for $bikeName'),
            const SizedBox(height: 4),
            const Text(
              'Try requesting another bike or select a different destination.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Try Again',
          textColor: Colors.white,
          onPressed: () {
            _fetchAndDisplayNearbyBikes();
          },
        ),
      ),
    );
  }

  void _resetToIdle() {
    setState(() {
      _isRequestingRide = false;
      _requestStatus = 'idle';
      _rideRequestError = null;
      _tempRequestId = null;
    });

    _fetchAndDisplayNearbyBikes();
  }

  void _handleRideRequestTimeout(dynamic data) {
    if (!mounted) return;

    print("Map_page: Ride request timed out: $data");

    setState(() {
      _isRequestingRide = false;
      _requestStatus = 'failed';
      _rideRequestError = 'Request timed out. No bike owners responded.';
      _tempRequestId = null;
    });

    _rideRequestTimeoutTimer?.cancel();
    _showErrorSnackbar(_rideRequestError!);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _rideRequestTimeoutTimer?.cancel();
    _wsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              mapController.complete(controller);
            },
            initialCameraPosition: CameraPosition(
              target: currentposition ?? const LatLng(45.7213, 21.21133),
              zoom: 15.0,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),

          // Search Area
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SearchArea(
              key: _searchKey,
              apiKey: google_api_key,
              onLocationSelected: _onDestinationSelected,
              mapController: mapController.future,
              hint: 'Where do you want to go?',
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 0),
              controller: _searchController,
            ),
          ),

          // Navigation Button
          Positioned(
            bottom: 200,
            right: 20,
            child: GestureDetector(
              onTap: smoothAnimateToCurrentPosition,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 118, 172, 198),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.navigation,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),

          // Dynamic Bottom Cards — AnimatedSwitcher gives a smooth slide-up transition
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
                return SlideTransition(position: slide, child: FadeTransition(opacity: animation, child: child));
              },
              child: _isRequestingRide && _tempRequestId != null
                  ? KeyedSubtree(key: const ValueKey('searching'), child: _buildSearchingForBikeCard())
                  : _alternativeBike != null
                      ? KeyedSubtree(key: const ValueKey('alternative'), child: _buildAlternativeBikeCard())
                      : atDestination
                          ? KeyedSubtree(key: const ValueKey('end'), child: _buildEndTripCard())
                          : _tripStarted && !atDestination
                              ? KeyedSubtree(key: const ValueKey('unlock'), child: _buildUnlockBikeCard())
                              : atBikeLocation && !atDestination
                                  ? KeyedSubtree(key: const ValueKey('start'), child: _buildStartTripCard())
                                  : rideAccepted && !navigatingToBike && !atBikeLocation && !atDestination
                                      ? KeyedSubtree(key: const ValueKey('navigate'), child: _buildNavigateToBikeCard())
                                      : showBikeDetails && selectedApiBike != null && !rideAccepted && !atDestination
                                          ? KeyedSubtree(key: const ValueKey('bikeinfo'), child: _showBikeInfo(selectedApiBike!))
                                          : destinationposition != null && !showBikeDetails && !rideAccepted && !navigatingToBike && !atBikeLocation && !atDestination && !isActiveTrip && !_isRequestingRide
                                              ? KeyedSubtree(key: const ValueKey('request'), child: _buildRideRequestCard())
                                              : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
        ],
      ),
    );
  }

  void _onDestinationSelected(
    LatLng location, {
    bool skipPriceEstimation = false,
  }) async {
    setState(() {
      destinationposition = location;
      markers.removeWhere((m) => m.markerId.value == "destination");
      markers.add(
        Marker(
          markerId: const MarkerId("destination"),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: "Destination"),
        ),
      );
    });

    if (currentposition != null) {
      await _getPolyline();
      if (!skipPriceEstimation) {
        await _getestimateprice();
      }
    }
  }

  Future<void> _cameraToPosition(LatLng position) async {
    final GoogleMapController controller = await mapController.future;
    CameraPosition cameraPosition = CameraPosition(
      target: position,
      zoom: 15.0,
    );
    controller.animateCamera(CameraUpdate.newCameraPosition(cameraPosition));
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await locationController.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await locationController.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await locationController.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await locationController.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    LocationData locationData = await locationController.getLocation();
    if (locationData.latitude != null && locationData.longitude != null) {
      currentposition = LatLng(locationData.latitude!, locationData.longitude!);
      _updateCurrentLocationMarker();
      _cameraToPosition(currentposition!);
    }

    // Throttle location updates
    DateTime? lastUpdate;
    locationController.onLocationChanged.listen((LocationData currentlocation) {
      if (currentlocation.latitude != null &&
          currentlocation.longitude != null) {
        // Throttle updates to every 3 seconds
        DateTime now = DateTime.now();
        if (lastUpdate != null && now.difference(lastUpdate!).inSeconds < 3) {
          return;
        }
        lastUpdate = now;

        LatLng newPosition = LatLng(
          currentlocation.latitude!,
          currentlocation.longitude!,
        );

        // Only update if position changed significantly (more than 10 meters)
        if (currentposition != null) {
          double distance = calculateDistance(
            currentposition!.latitude,
            currentposition!.longitude,
            newPosition.latitude,
            newPosition.longitude,
          );

          if (distance < 0.01) {
            // Less than 10 meters
            return;
          }
        }

        if (mounted) {
          setState(() {
            currentposition = newPosition;
            _updateCurrentLocationMarker();
            _checkIfAtBikeLocation();

            if (isActiveTrip) {
              _checkIfAtDestination();
            }
          });
          // Persist rider location to backend (fire-and-forget)
          AuthApiService.updateLocation(
            LocationUpdateRequest(
              latitude: newPosition.latitude,
              longitude: newPosition.longitude,
            ),
          );
        }

        // Update polylines based on current navigation state
        if (navigatingToBike && Bikelocation != null && !_isGettingPolyline) {
          _getPolylineToBike();
        } else if (destinationposition != null &&
            !navigatingToBike &&
            !_isGettingPolyline) {
          _getPolyline();
        }
      }
    });
  }

  void _updateCurrentLocationMarker() {
    markers.removeWhere(
      (m) =>
          m.markerId.value == "current_location" ||
          m.markerId.value == "bike_location",
    );

    if (isActiveTrip) {
      _addBikeMarkerAtCurrentPosition();
    } else {
      markers.add(
        Marker(
          markerId: const MarkerId("current_location"),
          position: currentposition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: "Current Location"),
        ),
      );
    }
    setState(() {});
  }

  Future<void> _addBikeMarkerAtCurrentPosition() async {
    if (currentposition == null) return;

    final bikeIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/bikemarker.png',
    );

    markers.add(
      Marker(
        markerId: const MarkerId("bike_location"),
        position: currentposition!,
        icon: bikeIcon,
        infoWindow: const InfoWindow(
          title: "Your Bike",
          snippet: "Currently riding",
        ),
      ),
    );

    Bikelocation = currentposition;
  }

  Future<void> _getPolyline() async {
    if (currentposition == null || destinationposition == null) {
      print("One of the positions is null.");
      return;
    }

    if (_isGettingPolyline) {
      print("Already fetching polyline, skipping...");
      return;
    }

    double distance = calculateDistance(
      currentposition!.latitude,
      currentposition!.longitude,
      destinationposition!.latitude,
      destinationposition!.longitude,
    );

    if (distance < 0.05) {
      print("Origin and destination too close, skipping polyline");
      if (mounted) {
        setState(() {
          polylines.clear();
        });
      }
      return;
    }

    if (_lastOrigin != null &&
        _lastDestination != null &&
        _coordinatesAreClose(_lastOrigin!, currentposition!, 0.001) &&
        _coordinatesAreClose(_lastDestination!, destinationposition!, 0.001)) {
      print("Polyline already exists for these coordinates");
      return;
    }

    _isGettingPolyline = true;
    print("Fetching polyline from: $currentposition to $destinationposition");

    List<LatLng> polylineCoordinates = [];
    PolylinePoints polylinePoints = PolylinePoints();

    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: google_api_key,
        request: PolylineRequest(
          origin: PointLatLng(
            currentposition!.latitude,
            currentposition!.longitude,
          ),
          destination: PointLatLng(
            destinationposition!.latitude,
            destinationposition!.longitude,
          ),
          mode: TravelMode.driving,
        ),
      );

      print("Polyline result status: ${result.status}");

      if (result.points.isNotEmpty) {
        for (var point in result.points) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }
        print("Polyline coordinates count: ${polylineCoordinates.length}");

        Polyline polyline = Polyline(
          polylineId: const PolylineId("route"),
          color: Colors.blue,
          width: 5,
          points: polylineCoordinates,
        );

        if (mounted) {
          setState(() {
            polylines.clear();
            polylines.add(polyline);
          });
        }

        _lastOrigin = LatLng(
          currentposition!.latitude,
          currentposition!.longitude,
        );
        _lastDestination = LatLng(
          destinationposition!.latitude,
          destinationposition!.longitude,
        );
        await Future.delayed(const Duration(milliseconds: 300));
        await smoothAnimateToCurrentPosition();

        print("Polyline added successfully");
      } else {
        print("No polyline points found");
        if (result.errorMessage != null) {
          print("Error: ${result.errorMessage}");
        }

        if (mounted) {
          setState(() {
            polylines.clear();
          });
        }
      }
    } catch (e) {
      print("Error getting polyline: $e");
      if (mounted) {
        setState(() {
          polylines.clear();
        });
      }
    } finally {
      _isGettingPolyline = false;
    }
  }

  bool _coordinatesAreClose(LatLng pos1, LatLng pos2, double tolerance) {
    return (pos1.latitude - pos2.latitude).abs() < tolerance &&
        (pos1.longitude - pos2.longitude).abs() < tolerance;
  }

  Future<void> _getPolylineToBike() async {
    if (currentposition == null || Bikelocation == null) {
      print("One of the positions is null.");
      return;
    }
    if (_isGettingPolyline) {
      print("Already fetching polyline, skipping...");
      return;
    }

    _isGettingPolyline = true;
    print("Fetching polyline to bike: $currentposition to $Bikelocation");

    List<LatLng> polylineCoordinates = [];
    PolylinePoints polylinePoints = PolylinePoints();

    try {
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: google_api_key,
        request: PolylineRequest(
          origin: PointLatLng(
            currentposition!.latitude,
            currentposition!.longitude,
          ),
          destination: PointLatLng(
            Bikelocation!.latitude,
            Bikelocation!.longitude,
          ),
          mode: TravelMode.walking,
        ),
      );

      print("Polyline result status: ${result.status}");

      if (result.points.isNotEmpty) {
        for (var point in result.points) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }
        print("Polyline coordinates count: ${polylineCoordinates.length}");

        Polyline polyline = Polyline(
          polylineId: const PolylineId("route_to_bike"),
          color: Colors.orange,
          width: 5,
          points: polylineCoordinates,
        );

        // IMPORTANT: Clear and set polylines in one setState
        if (mounted) {
          setState(() {
            polylines.clear();
            polylines.add(polyline);
          });
        }

        print("Polyline to bike added successfully");
      } else {
        print("No polyline points found");
        if (result.errorMessage != null) {
          print("Error: ${result.errorMessage}");
        }
        // Clear polylines if no route found
        if (mounted) {
          setState(() {
            polylines.clear();
          });
        }
      }
    } catch (e) {
      print("Error getting polyline to bike: $e");
      // Clear polylines on error
      if (mounted) {
        setState(() {
          polylines.clear();
        });
      }
    } finally {
      _isGettingPolyline = false;
    }
  }

  Future<void> _fetchAndDisplayNearbyBikes() async {
    if (currentposition == null) {
      print("Current position is null, cannot fetch nearby bikes.");
      if (mounted) {
        setState(() {
          _nearbyBikesError =
              "Could not get your current location to find bikes.";
        });
      }
      return;
    }

    // 🔒 Prevent multiple simultaneous requests
    if (_isLoadingBikes) {
      print("Already loading bikes, skipping request.");
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingBikes = true;
        _nearbyBikesError = null;
        _fetchedNearbyBikes.clear();
      });
    }

    try {
      final ApiResponse<List<NearbyBike>> response =
          await RideApiService.getNearbyBikes(
            latitude: currentposition!.latitude,
            longitude: currentposition!.longitude,
          );

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _fetchedNearbyBikes = response.data!;
          });
          await _addFetchedBikeMarkers();

          if (_fetchedNearbyBikes.isEmpty) {
            print("No nearby bikes found.");
            // Optionally set a different message for empty results
            setState(() {
              _nearbyBikesError =
                  "No bikes available nearby. Try a different location.";
            });
          } else {
            print("Fetched ${_fetchedNearbyBikes.length} nearby bikes.");
          }
        } else {
          setState(() {
            _nearbyBikesError =
                response.error ?? "Failed to fetch nearby bikes.";
          });
          _showErrorSnackbar(_nearbyBikesError ?? "Could not load bikes.");
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _nearbyBikesError = "An error occurred: ${e.toString()}";
        });
        _showErrorSnackbar("An error occurred while loading bikes.");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBikes = false; // ✅ Always clear loading state
        });
      }
    }
  }

  Future<void> _addFetchedBikeMarkers() async {
    markers.removeWhere((m) => m.markerId.value.startsWith("bike_api_"));

    if (_fetchedNearbyBikes.isEmpty) return;

    final icon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/bikemarker.png',
    );

    for (var bike in _fetchedNearbyBikes) {
      final marker = Marker(
        markerId: MarkerId("bike_api_${bike.id}"),
        position: LatLng(bike.location.latitude, bike.location.longitude),
        icon: icon,
        infoWindow: InfoWindow(
          title: bike.bikeName,
          snippet: "Brand: ${bike.brand}, Model: ${bike.model}",
        ),
        onTap: () {
          if (mounted) {
            setState(() {
              selectedApiBike = bike;
              showBikeDetails = true;
            });
          }
        },
      );
      markers.add(marker);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Widget _showBikeInfo(NearbyBike bike) {
    String distanceText = "${bike.distance.toStringAsFixed(1)} km away";
    if (currentposition != null) {
      double distanceInKm = calculateDistance(
        currentposition!.latitude,
        currentposition!.longitude,
        bike.location.latitude,
        bike.location.longitude,
      );
      distanceText = '${distanceInKm.toStringAsFixed(1)} km away';
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  bike.bikeName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      showBikeDetails = false;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildBikeImage(bike),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color.fromARGB(
                  255,
                  118,
                  172,
                  198,
                ).withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 16,
                    color: Color.fromARGB(255, 118, 172, 198),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    distanceText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 162, 78, 9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Brand: ${bike.brand} - Model: ${bike.model}'),
            const SizedBox(height: 4),
            if (bike.batteryLevel != null) ...[
              Text('Battery: 🔋 ${bike.batteryLevel}%'),
              const SizedBox(height: 4),
            ],
            if (bike.bikeAddress != null && bike.bikeAddress!.isNotEmpty) ...[
              Text('Address: ${bike.bikeAddress}'),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;

    return distance;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  Future<void> smoothAnimateToCurrentPosition() async {
    if (currentposition == null) return;

    final GoogleMapController controller = await mapController.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: currentposition!, zoom: 14.0),
      ),
    );
  }

  Widget _buildRideRequestCard() {
    String priceDisplay;
    if (_isEstimatingPrice) {
      priceDisplay = 'Estimating...';
    } else if (_priceEstimationError != null) {
      priceDisplay = 'Error';
    } else if (estimatedPrice != null) {
      priceDisplay = '${estimatedPrice!.toStringAsFixed(2)} €';
    } else {
      priceDisplay = 'N/A';
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color.fromARGB(
                  255,
                  118,
                  172,
                  198,
                ).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color.fromARGB(
                    255,
                    118,
                    172,
                    198,
                  ).withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Estimated Price',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_isEstimatingPrice)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      priceDisplay,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color:
                            _priceEstimationError != null
                                ? Colors.red
                                : const Color.fromARGB(255, 118, 172, 198),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed:
                        (estimatedPrice != null &&
                                !_isEstimatingPrice &&
                                _priceEstimationError == null)
                            ? _startRideRequest
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF76ACC6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Request Ride',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _cancelrequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 8, 8, 8),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color.fromARGB(255, 242, 243, 244),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _cancelrequest() {
    setState(() {
      destinationposition = null;
      polylines.clear();
      markers.removeWhere((marker) => marker.markerId.value == 'destination');
      _lastOrigin = null;
      _lastDestination = null;
      print("Request stopped");
    });
    _searchController.clear();
    _searchKey = UniqueKey();
  }

  void _handleRideAccepted(Map<String, dynamic> responseData) {
    print("🔥 _handleRideAccepted called with data: $responseData");

    setState(() {
      rideAccepted = true;
      acceptedRideData = responseData;

      tripId = responseData['trip_id']?.toString();
      bikeOwnerName = responseData['owner_username']?.toString();
      chatRoomId = responseData['chat_room_id']?.toString();

      final bikeData = responseData['bike'] as Map<String, dynamic>?;
      final destData = responseData['destination'] as Map<String, dynamic>?;

      if (bikeData != null) {
        final bikeLat = bikeData['latitude'];
        final bikeLng = bikeData['longitude'];

        if (bikeLat != null && bikeLng != null) {
          Bikelocation = LatLng(
            (bikeLat is num)
                ? bikeLat.toDouble()
                : double.parse(bikeLat.toString()),
            (bikeLng is num)
                ? bikeLng.toDouble()
                : double.parse(bikeLng.toString()),
          );
          print("🔥 Bike location set to: $Bikelocation");
        }
      }

      if (destData != null) {
        final destLat = destData['latitude'];
        final destLng = destData['longitude'];

        if (destLat != null && destLng != null) {
          finalDestination = LatLng(
            (destLat is num)
                ? destLat.toDouble()
                : double.parse(destLat.toString()),
            (destLng is num)
                ? destLng.toDouble()
                : double.parse(destLng.toString()),
          );
        }
      }

      destinationposition = null;
      polylines.clear();
      markers.removeWhere((m) => m.markerId.value == "destination");
      markers.removeWhere((m) => m.markerId.value.startsWith("bike_"));
    });

    // Wait a moment for state to update, then navigate
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        print("🔥 About to call _navigatetobike()");
        print("🔥 currentposition: $currentposition");
        print("🔥 Bikelocation: $Bikelocation");
      }
    });
  }

  Future<void> _startTrip() async {
    if (tripId == null) {
      print("No trip ID available");
      _showErrorSnackbar("No trip ID available");
      return;
    }

    print("Starting trip with ID: $tripId");

    try {
      // Call the backend API to start the trip
      final ApiResponse<StartTripResponse> response =
          await RideApiService.startTrip(tripId!);

      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          activeTripId = tripId;
          tripId = null;
          _tripStarted = true;
          rideAccepted = false;
          navigatingToBike = false;
          atBikeLocation = false;
          acceptedRideData = null;
        });

        if (widget.onTripStatusChanged != null) {
          widget.onTripStatusChanged!(true, {
            'tripId': activeTripId,
            'bikeOwnerName': bikeOwnerName,
            'bikeOwnerId': bikeOwnerId,
            'chatRoomId': chatRoomId,
          });
        }

        _showSuccessSnackbar(
          '🔓 Check chat for your unlock code, then tap "I\'ve Unlocked the Bike"',
        );
      } else {
        // API call failed
        print("Failed to start trip: ${response.error}");
        _showErrorSnackbar(
          response.error ?? "Failed to start trip. Please try again.",
        );
      }
    } catch (e) {
      if (!mounted) return;
      print("Exception during trip start: $e");
      _showErrorSnackbar("An error occurred while starting the trip.");
    }
  }

  Future<void> _beginTrip() async {
    if (activeTripId == null) return;
    setState(() => _isBeginningTrip = true);

    try {
      final response = await RideApiService.beginTrip(activeTripId!);
      if (!mounted) return;

      if (response.success) {
        setState(() {
          _tripStarted = false;
          _isBeginningTrip = false;
          isActiveTrip = true;
          polylines.clear();
          if (finalDestination != null) {
            destinationposition = finalDestination;
            markers.removeWhere((m) => m.markerId.value == "destination");
            markers.add(
              Marker(
                markerId: const MarkerId("destination"),
                position: finalDestination!,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueBlue,
                ),
                infoWindow: const InfoWindow(title: "Destination"),
              ),
            );
          }
        });
        _showSuccessSnackbar('🚴‍♂️ Ride started! Navigate to your destination.');
        if (currentposition != null && finalDestination != null) {
          await _getPolyline();
        }
      } else {
        setState(() => _isBeginningTrip = false);
        _showErrorSnackbar(response.error ?? 'Failed to begin trip.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBeginningTrip = false);
      _showErrorSnackbar('Error beginning trip.');
    }
  }

  Widget _buildUnlockBikeCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_open, color: Colors.orange, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Unlock the Bike',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check the chat for your unlock code.\nEnter it on the bike keypad, then tap the button below.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isBeginningTrip ? null : _beginTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isBeginningTrip
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Starting ride...',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ],
                      )
                    : const Text(
                        "I've Unlocked the Bike",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlternativeBikeCard() {
    final alt = _alternativeBike!;
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'That bike was just taken',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Alternative available: ${alt.name} (${alt.brand} ${alt.model})'),
            Text('Distance: ${alt.distanceKm.toStringAsFixed(1)} km away'),
            if (_estimatedAlternativePrice != null)
              Text('Price: €${_estimatedAlternativePrice!.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _acceptAlternativeBike,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color.fromARGB(255, 118, 172, 198),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Use This Bike',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _dismissAlternativeBike,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double? _estimatedAlternativePrice;

  void _acceptAlternativeBike() {
    if (_alternativeBike == null || _newPriceToken == null) return;
    setState(() {
      _priceToken = _newPriceToken;
      estimatedPrice = _estimatedAlternativePrice;
      _alternativeBike = null;
      _newPriceToken = null;
      _estimatedAlternativePrice = null;
      _isRequestingRide = false;
      _requestStatus = 'idle';
    });
    _showSuccessSnackbar(
        'Alternative bike selected. Tap "Request Ride" to confirm.');
  }

  void _dismissAlternativeBike() {
    setState(() {
      _alternativeBike = null;
      _newPriceToken = null;
      _estimatedAlternativePrice = null;
      _isRequestingRide = false;
      _requestStatus = 'idle';
    });
    _cancelrequest();
  }

  Future<void> _RequestRide() async {
    if (!_sessionManager.isMainWSConnected) {
      bool reconnected = false;
      if (!_sessionManager.isMainWSConnecting &&
          _sessionManager.isAuthenticated) {
        print("Attempting to reconnect main WebSocket before ride request...");
        reconnected = await _sessionManager.attemptReconnectMainWebSocket();
      }
      if (!reconnected) {
        setState(() {
          _requestStatus = 'failed';
          _rideRequestError =
              "Notification service not connected. Please try again.";
        });
        _showErrorSnackbar(
          "Notification service not connected. Please try again.",
        );
        return;
      }
      print(
        "WebSocket reconnected successfully, proceeding with ride request.",
      );
    }

    if (currentposition == null) {
      setState(() {
        _requestStatus = 'failed';
        _rideRequestError = "Could not determine your current location.";
      });
      _showErrorSnackbar("Could not determine your current location.");
      return;
    }

    if (destinationposition == null) {
      setState(() {
        _requestStatus = 'failed';
        _rideRequestError = "Please select a destination first.";
      });
      _showErrorSnackbar("Please select a destination first.");
      return;
    }

    if (_priceToken == null) {
      setState(() {
        _requestStatus = 'failed';
        _rideRequestError =
            "Price not estimated. Please select destination again.";
      });
      _showErrorSnackbar(
        "Price not estimated. Please select destination again.",
      );
      return;
    }

    String? originAddress = await _getAddressFromLatLng(currentposition!);
    String? destinationAddress;

    if (widget.initialDestination != null &&
        widget.initialDestination!.isNotEmpty &&
        _searchController.text == widget.initialDestination) {
      destinationAddress = widget.initialDestination;
    } else if (_searchController.text.trim().isNotEmpty) {
      destinationAddress = _searchController.text.trim();
    } else {
      destinationAddress = await _getAddressFromLatLng(destinationposition!);
    }

    if (originAddress == null) {
      setState(() {
        _requestStatus = 'failed';
        _rideRequestError =
            "Could not determine your starting address. Please try again.";
      });
      _showErrorSnackbar(
        "Could not determine your starting address. Please try again.",
      );
      return;
    }

    if (destinationAddress == null) {
      setState(() {
        _requestStatus = 'failed';
        _rideRequestError =
            "Could not determine your destination address. Please try again.";
      });
      _showErrorSnackbar(
        "Could not determine your destination address. Please try again.",
      );
      return;
    }

    const String paymentType = "card";

    final rideApiRequest = RideRequestRequest(
      pickupLatitude: currentposition!.latitude,
      pickupLongitude: currentposition!.longitude,
      destinationLatitude: destinationposition!.latitude,
      destinationLongitude: destinationposition!.longitude,
      destinationAddress: destinationAddress,
      originAddress: originAddress,
      paymentType: paymentType,
      priceToken: _priceToken!,
    );

    try {
      final ApiResponse<RideRequestResponse> response =
          await RideApiService.requestRide(rideApiRequest);

      if (!mounted) return;

      if (response.success && response.data != null) {
        final data = response.data!;
        if (data.preferredBikeUnavailable) {
          setState(() {
            _isRequestingRide = false;
            _requestStatus = 'idle';
            _alternativeBike = data.alternativeBike;
            _newPriceToken = data.newPriceToken;
            _estimatedAlternativePrice = data.estimatedPrice;
          });
        } else {
          setState(() {
            _tempRequestId = data.tempRequestId;
            _requestStatus = 'waiting';
            _rideRequestError = null;
          });
          _showSuccessSnackbar(
            data.message.isNotEmpty
                ? data.message
                : "Request sent! Waiting for a bike...",
          );
          _startRequestTimeoutTimer();
        }
      } else {
        setState(() {
          _requestStatus = 'failed';
          _rideRequestError =
              response.error ?? "Failed to request ride. Please try again.";
        });
        _showErrorSnackbar(_rideRequestError!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requestStatus = 'failed';
        _rideRequestError = "An unexpected error occurred: ${e.toString()}";
      });
      _showErrorSnackbar(_rideRequestError!);
    }
  }

  Future<void> _getestimateprice() async {
    if (currentposition == null || destinationposition == null) {
      print("Cannot estimate price: Origin or destination is missing.");
      if (mounted) {
        setState(() {
          _priceEstimationError = "Please set both origin and destination.";
          estimatedPrice = null;
          _priceToken = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isEstimatingPrice = true;
        _priceEstimationError = null;
        estimatedPrice = null;
        _priceToken = null;
      });
    }

    final request = EstimatePriceRequest(
      pickupLatitude: currentposition!.latitude,
      pickupLongitude: currentposition!.longitude,
      destinationLatitude: destinationposition!.latitude,
      destinationLongitude: destinationposition!.longitude,
    );

    try {
      final ApiResponse<EstimatePriceResponse> response =
          await RideApiService.estimatePrice(request);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            estimatedPrice = response.data!.estimatedPrice;
            _priceToken = response.data!.priceToken;
            print(
              "Price estimated: ${response.data!.estimatedPrice}, Token: ${response.data!.priceToken}",
            );
          });
        } else {
          setState(() {
            _priceEstimationError =
                response.error ?? "Failed to estimate price.";
            estimatedPrice = null;
            _priceToken = null;
          });
          print("Price estimation failed: ${response.error}");
          _showErrorSnackbar(
            _priceEstimationError ?? "Could not estimate price.",
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _priceEstimationError = "An error occurred: ${e.toString()}";
          estimatedPrice = null;
          _priceToken = null;
        });
        print("Exception during price estimation: $e");
        _showErrorSnackbar("An error occurred while estimating the price.");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEstimatingPrice = false;
        });
      }
    }
  }

  Future<void> _navigatetobike() async {
    if (currentposition == null || Bikelocation == null) {
      print("Current position or bike location is null");
      return;
    }

    print("🔥 Starting navigation to bike at: $Bikelocation");

    // Create bike marker first
    final bikeMarker = Marker(
      markerId: const MarkerId("bike_location"),
      position: Bikelocation!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      infoWindow: InfoWindow(
        title: "Your Bike",
        snippet: acceptedRideData?['bike']['name'] ?? 'Bike',
      ),
    );

    setState(() {
      navigatingToBike = true;

      markers.removeWhere((m) => m.markerId.value == "bike_location");

      markers.add(bikeMarker);

      polylines.clear();
    });

    await _getPolylineToBike();

    print("✅ Navigation to bike setup complete");
    print("✅ Bike marker added at: $Bikelocation");
    print("✅ navigatingToBike = $navigatingToBike");
  }

  Widget _buildNavigateToBikeCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success icon
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 12),

            // Title
            const Text(
              'Ride Request Accepted!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),

            // Payment info
            Text(
              'Payment: ${acceptedRideData?['payment']['amount']?.toStringAsFixed(2) ?? '0.00'} €',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),

            // Bike info
            Text(
              'Bike: ${acceptedRideData?['bike']['name'] ?? 'Unknown'}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),

            // Owner info
            if (acceptedRideData?['owner_username'] != null) ...[
              Text(
                'Owner: ${acceptedRideData!['owner_username']}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _navigatetobike,
                icon: const Icon(Icons.navigation, color: Colors.white),
                label: const Text(
                  'Navigate to Bike',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Instruction text
            const Text(
              'Click above to start navigation to your bike',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartTripCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pedal_bike, color: Colors.green, size: 48),
            const SizedBox(height: 12),
            const Text(
              'You\'ve Arrived!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You are now at the bike location',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  print("Start Trip button pressed!");
                  _startTrip();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Start Trip',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _checkIfAtBikeLocation() {
    if (currentposition != null && Bikelocation != null && navigatingToBike) {
      double distance = calculateDistance(
        currentposition!.latitude,
        currentposition!.longitude,
        Bikelocation!.latitude,
        Bikelocation!.longitude,
      );

      if (distance <= 0.05 && !atBikeLocation) {
        setState(() {
          atBikeLocation = true;
        });

        print(
          "🎉 User arrived at bike location! Distance: ${distance.toStringAsFixed(3)} km",
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 You have arrived at the bike location!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else if (distance > 0.05 && atBikeLocation) {
        setState(() {
          atBikeLocation = false;
        });
        print(
          "❌ User moved away from bike. Distance: ${distance.toStringAsFixed(3)} km",
        );
      }

      if (navigatingToBike) {
        print("Current distance to bike: ${distance.toStringAsFixed(3)} km");
      }
    }
  }

  void _checkIfAtDestination() {
    if (currentposition != null &&
        destinationposition != null &&
        isActiveTrip) {
      double distance = calculateDistance(
        currentposition!.latitude,
        currentposition!.longitude,
        destinationposition!.latitude,
        destinationposition!.longitude,
      );

      if (distance <= 0.05 && !atDestination) {
        setState(() {
          atDestination = true;
        });

        print(
          "🎯 User arrived at destination! Distance: ${distance.toStringAsFixed(3)} km",
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎯 You have arrived at your destination!'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      } else if (distance > 0.05 && atDestination) {
        setState(() {
          atDestination = false;
        });
      }
    }
  }

  Widget _buildEndTripCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag, color: Colors.blue, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Destination Reached!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You have arrived at your destination',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _endTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'End Trip',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _endTrip() async {
    if (activeTripId == null) {
      print("No active trip ID available for ending trip");
      _showErrorSnackbar("No active trip ID available");
      return;
    }

    print("Ending trip with ID: $activeTripId");

    try {
      // Call the backend API to end the trip
      final ApiResponse<EndTripResponse> response =
          await RideApiService.endTrip(activeTripId!);

      if (!mounted) return;

      if (response.success && response.data != null) {
        final endData = response.data!;
        final endedTripId = activeTripId;

        if (widget.onTripStatusChanged != null) {
          widget.onTripStatusChanged!(false, null);
        }

        setState(() {
          isActiveTrip = false;
          destinationposition = null;
          finalDestination = null;
          atDestination = false;
          Bikelocation = null;
          activeTripId = null;
          bikeOwnerName = null;
          bikeOwnerId = null;
          chatRoomId = null;
          polylines.clear();
          markers.removeWhere(
            (marker) =>
                marker.markerId.value == 'destination' ||
                marker.markerId.value == 'bike_location',
          );
        });

        _updateCurrentLocationMarker();
        _searchController.clear();
        _searchKey = UniqueKey();

        // Show receipt dialog then offer rating
        if (mounted) {
          await _showTripReceiptDialog(endData, endedTripId);
        }

        await _fetchAndDisplayNearbyBikes();
      } else {
        // API call failed
        print("Failed to end trip: ${response.error}");
        _showErrorSnackbar(
          response.error ?? "Failed to end trip. Please try again.",
        );
      }
    } catch (e) {
      if (!mounted) return;
      print("Exception during trip end: $e");
      _showErrorSnackbar("An error occurred while ending the trip.");
    }
  }

  Future<void> _showTripReceiptDialog(
      EndTripResponse data, String? tripId) async {
    final td = data.tripDetails;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Trip Complete!'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              _receiptRow('Distance', '${td.actualDistanceKm.toStringAsFixed(2)} km'),
              _receiptRow('Duration', '${(td.durationHours * 60).toStringAsFixed(0)} min'),
              _receiptRow('Estimated price', '€${td.estimatedPrice.toStringAsFixed(2)}'),
              if (td.extraCharge > 0)
                _receiptRow('Extra charge', '€${td.extraCharge.toStringAsFixed(2)}'),
              const Divider(),
              _receiptRow('Total paid', '€${td.finalPrice.toStringAsFixed(2)}',
                  bold: true),
            ],
          ),
        ),
        actions: [
          if (tripId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showMapRatingDialog(tripId);
              },
              child: const Text('Rate This Trip'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 118, 172, 198),
              foregroundColor: Colors.white,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontSize: bold ? 16 : 14,
              )),
        ],
      ),
    );
  }

  Future<void> _showMapRatingDialog(String tripId) async {
    int selectedRating = 0;
    final reviewController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Rate your ride'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    icon: Icon(
                      star <= selectedRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                    onPressed: () =>
                        setDialogState(() => selectedRating = star),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reviewController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Leave a review (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: selectedRating == 0
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await RideApiService.rateTrip(
                        tripId,
                        RateTripRequest(
                          rating: selectedRating,
                          review: reviewController.text.trim().isEmpty
                              ? null
                              : reviewController.text.trim(),
                        ),
                      );
                      if (mounted) {
                        _showSuccessSnackbar('Thanks for your rating!');
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    reviewController.dispose();
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color.fromARGB(255, 50, 85, 26),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<String?> _getAddressFromLatLng(LatLng position) async {
    try {
      print("Lat: ${position.latitude}, Lng: ${position.longitude}");
      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return "${p.street}, ${p.locality}, ${p.postalCode}, ${p.country}";
      }
    } catch (e) {
      print("Error getting address from latlng: $e");
    }
    return null;
  }

  Widget _buildSearchingForBikeCard() {
    String title;
    String subtitle;
    Widget icon;

    switch (_requestStatus) {
      case 'preparing':
        icon = const CircularProgressIndicator(
          color: Color.fromARGB(255, 118, 172, 198),
        );
        title = 'Preparing your request...';
        subtitle = 'Validating location and connecting to service.';
        break;
      case 'waiting':
        icon = const CircularProgressIndicator(
          color: Color.fromARGB(255, 118, 172, 198),
        );
        title = 'Searching for available bikes...';
        subtitle =
            'We\'ve sent your request to nearby bike owners. Please wait for a response.';
        break;
      case 'cancelling':
        icon = const CircularProgressIndicator(color: Colors.orange);
        title = 'Cancelling request...';
        subtitle = 'Please wait while we cancel your ride request.';
        break;
      case 'failed':
        icon = const Icon(Icons.error, color: Colors.red, size: 48);
        title = 'Request Failed';
        subtitle =
            _rideRequestError ?? 'Something went wrong. Please try again.';
        break;
      default:
        icon = const CircularProgressIndicator(
          color: Color.fromARGB(255, 118, 172, 198),
        );
        title = 'Processing...';
        subtitle = 'Please wait.';
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color:
                    _requestStatus == 'failed'
                        ? Colors.red
                        : _requestStatus == 'cancelling'
                        ? Colors.orange
                        : const Color.fromARGB(255, 118, 172, 198),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),

            // Show estimated price only when waiting
            if (_requestStatus == 'waiting' && estimatedPrice != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(
                    255,
                    118,
                    172,
                    198,
                  ).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color.fromARGB(
                      255,
                      118,
                      172,
                      198,
                    ).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Trip Cost',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${estimatedPrice!.toStringAsFixed(2)} €',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 118, 172, 198),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Cancel/Retry button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _requestStatus == 'cancelling'
                        ? null // Disable while cancelling
                        : _requestStatus == 'failed'
                        ? _retryRequest
                        : _cancelRideRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _requestStatus == 'failed'
                          ? Colors.orange
                          : _requestStatus == 'cancelling'
                          ? Colors.grey
                          : Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _requestStatus == 'cancelling'
                        ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Cancelling...',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        )
                        : Text(
                          _requestStatus == 'failed'
                              ? 'Try Again'
                              : 'Cancel Request',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
              ),
            ),

            // Timeout warning only when waiting
            if (_requestStatus == 'waiting') ...[
              const SizedBox(height: 12),
              const Text(
                'Request will timeout in 5 minutes if no owner responds',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBikeImage(NearbyBike bike) {
    // bikeImage field from the model
    final String? bikeImageUrl = bike.bikeImage;

    if (bikeImageUrl == null || bikeImageUrl.isEmpty) {
      //  Fallback for no image
      return Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(
            Icons.pedal_bike,
            size: 80,
            color: Color.fromARGB(255, 118, 172, 198),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: bikeImageUrl,
        height: 150,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder:
            (context, url) => Container(
              height: 150,
              width: double.infinity,
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color.fromARGB(255, 118, 172, 198),
                ),
              ),
            ),
        errorWidget:
            (context, url, error) => Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 40, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'Image unavailable',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  void _startRequestTimeoutTimer() {
    _rideRequestTimeoutTimer?.cancel();
    _rideRequestTimeoutTimer = Timer(const Duration(minutes: 5), () async {
      if (!mounted || !_isRequestingRide || _requestStatus != 'waiting') return;
      final idToCancel = _tempRequestId;
      setState(() {
        _isRequestingRide = false;
        _requestStatus = 'idle';
        _rideRequestError = 'Request timed out. No bike owners responded.';
        _tempRequestId = null;
      });
      _showErrorSnackbar('Request timed out. Please try again.');
      if (idToCancel != null) {
        await RideApiService.cancelRideRequest(idToCancel);
      }
    });
  }

  Future<void> _startRideRequest() async {
    setState(() {
      _isRequestingRide = true;
      _requestStatus = 'preparing';
      _rideRequestError = null;
    });

    await _RequestRide();
  }

  void _cancelRideRequest() async {
    if (_tempRequestId == null) {
      _showErrorSnackbar('No request to cancel');
      return;
    }

    // Show loading state
    setState(() {
      _requestStatus = 'cancelling';
    });

    try {
      print("Cancelling ride request with ID: $_tempRequestId");

      final ApiResponse<CancelRideRequestResponse> response =
          await RideApiService.cancelRideRequest(_tempRequestId!);

      if (!mounted) return;

      if (response.success && response.data != null) {
        print("Ride request cancelled successfully: ${response.data!.message}");

        // Cancel timeout timer
        _rideRequestTimeoutTimer?.cancel();

        // Reset state clear everything
        setState(() {
          _isRequestingRide = false;
          _requestStatus = 'idle';
          _tempRequestId = null;
          _rideRequestError = null;
          destinationposition = null;
          polylines.clear();
          estimatedPrice = null;
          _priceToken = null;
          _priceEstimationError = null;
        });

        _cancelrequest();

        // Show success message with details
        _showSuccessSnackbar(
          '${response.data!.message}\n${response.data!.nextStep}',
        );

        print("Owner notified: ${response.data!.ownerNotified}");
        print(
          "Bike '${response.data!.bikeStatus.name}' is now ${response.data!.bikeStatus.status}",
        );
      } else {
        // Handle API error
        setState(() {
          _requestStatus = 'failed';
          _rideRequestError = response.error ?? 'Failed to cancel request';
        });
        _showErrorSnackbar(_rideRequestError!);
        print("Cancel request failed: ${response.error}");
      }
    } catch (e) {
      if (!mounted) return;

      // Handle exception
      setState(() {
        _requestStatus = 'failed';
        _rideRequestError = 'Error cancelling request: ${e.toString()}';
      });
      _showErrorSnackbar(_rideRequestError!);
      print("Exception during cancel request: $e");
    }
  }

  void _retryRequest() {
    setState(() {
      _requestStatus = 'idle';
      _rideRequestError = null;
      _isRequestingRide = false;
    });
  }
}
