import 'package:flutter/material.dart';
import 'package:paddleapp/pages/Map_page.dart';
import 'package:paddleapp/pages/Account_page.dart';
import 'package:paddleapp/pages/Rides_page.dart';
import 'package:paddleapp/pages/chat_page.dart';
import 'package:paddleapp/Apiendpoints/models/auth_models.dart';
import 'package:paddleapp/Apiendpoints/apiservices/chat_api_service.dart';
import 'dart:async';

class Navbar extends StatefulWidget {
  final String? initialDestination;
  final double? initialDestinationLat;
  final double? initialDestinationLng;
  final bool tripActive;
  final User? user;

  const Navbar({
    super.key,
    this.initialDestination,
    this.initialDestinationLat,
    this.initialDestinationLng,
    this.tripActive = false,
    this.user,
  });

  @override
  State<Navbar> createState() => _NavbarState();
}

class _NavbarState extends State<Navbar> {
  int selectedIndex = 0;
  late bool tripActive;
  User? _currentUser;

  //  Store trip data for chat
  Map<String, dynamic>? _tripData;

  //  ChatWebSocketService and subscription
  final ChatWebSocketService _chatService = ChatWebSocketService();
  StreamSubscription<String>? _tripStatusSubscription;

  @override
  void initState() {
    super.initState();
    tripActive = widget.tripActive;
    _currentUser = widget.user;

    if (widget.initialDestination != null) {
      selectedIndex = 0;
    }

    if (_currentUser == null) {
      print(
        "Navbar initState: User is null. Account page might not have data if accessed directly.",
      );
    }

    // ✅ Listen to trip status changes
    _setupTripStatusListener();
  }

  @override
  void dispose() {
    //  Cancel subscription
    _tripStatusSubscription?.cancel();
    super.dispose();
  }

  //  trip status listener
  void _setupTripStatusListener() {
    _tripStatusSubscription = _chatService.tripStatusStream.listen((status) {
      print("Navbar: Trip status changed to: $status");

      if (status == 'completed' || status == 'cancelled' || status == 'ended') {
        print("Navbar: Trip ended, hiding chat tab");

        if (mounted) {
          setState(() {
            tripActive = false;
            _tripData = null;

            // If currently on chat tab, switch to map tab
            if (selectedIndex >= currentDestinations.length) {
              selectedIndex = 0; // Switch to map tab
            }
          });
        }
      }
    });
  }

  List<Widget> get currentScreens {
    Widget accountPageWidget;
    if (_currentUser != null) {
      accountPageWidget = Account_page(user: _currentUser!);
    } else {
      accountPageWidget = const Center(
        child: Text(
          "User data not available. Please try logging in again.",
          textAlign: TextAlign.center,
        ),
      );
    }

    return [
      Map_page(
        initialDestination: widget.initialDestination,
        initialDestinationLat: widget.initialDestinationLat,
        initialDestinationLng: widget.initialDestinationLng,
        onTripStatusChanged: _updateTripStatus,
      ),
      const Rides_page(),
      accountPageWidget,
      if (tripActive)
        ChatPage(
          tripId: _tripData?['tripId'],
          bikeOwnerName: _tripData?['bikeOwnerName'] ?? 'Bike Owner',
          bikeOwnerId: _tripData?['bikeOwnerId'],
        ),
    ];
  }

  List<NavigationDestination> get currentDestinations {
    return [
      const NavigationDestination(icon: Icon(Icons.map_sharp), label: "Map"),
      const NavigationDestination(
        icon: Icon(Icons.bike_scooter),
        label: "Rides",
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_2_rounded),
        label: "Profile",
      ),
      if (tripActive)
        const NavigationDestination(icon: Icon(Icons.chat), label: "Chat"),
    ];
  }

  void _updateTripStatus(bool isActive, Map<String, dynamic>? tripData) {
    if (mounted) {
      setState(() {
        tripActive = isActive;
        _tripData = tripData; // Store trip data

        if (!isActive && selectedIndex >= currentDestinations.length) {
          selectedIndex = 0; // Switch to map tab
        }
      });

      // Debug print
      print("Navbar: Trip status updated - Active: $isActive, Data: $tripData");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (mounted) {
            if (index < currentDestinations.length) {
              setState(() {
                selectedIndex = index;
              });
            }
          }
        },
        destinations: currentDestinations,
      ),
      body: IndexedStack(index: selectedIndex, children: currentScreens),
    );
  }
}
