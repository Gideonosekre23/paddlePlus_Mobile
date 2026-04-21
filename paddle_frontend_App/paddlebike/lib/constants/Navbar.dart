import 'package:flutter/material.dart';
import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddlebike/Apiendpoints/models/auth_models.dart';
import 'package:paddlebike/pages/Account_page.dart';
import 'package:paddlebike/pages/Owner_Account_page.dart';
import 'package:paddlebike/pages/Rides_page.dart';
import 'package:paddlebike/pages/chat_page.dart';
import 'dart:async';

// MODEL FOR ACTIVE TRIPS
class ActiveTrip {
  final String tripId;
  final String chatRoomId;
  final String riderName;
  final int riderId;
  final String bikeName;
  final DateTime startTime;

  ActiveTrip({
    required this.tripId,
    required this.chatRoomId,
    required this.riderName,
    required this.riderId,
    required this.bikeName,
    required this.startTime,
  });

  @override
  String toString() => 'Trip($tripId, $riderName, $bikeName)';
}

class Navbar extends StatefulWidget {
  final bool tripActive;
  const Navbar({super.key, this.tripActive = false});

  @override
  State<Navbar> createState() => _NavbarState();
}

class _NavbarState extends State<Navbar> {
  // MULTIPLE CHAT INSTANCES
  List<ActiveTrip> activeTrips = [];
  int selectedIndex = 0;
  final UserSessionManager _sessionManager = UserSessionManager();
  User? currentUser;
  StreamSubscription? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    currentUser = _sessionManager.currentUser;
    print("🔔 Navbar: Initializing multiple chat support...");
    _listenForTripNotifications();
  }

  @override
  void dispose() {
    print("🔔 Navbar: Disposing WebSocket listener...");
    _notificationSubscription?.cancel();
    super.dispose();
  }

  // 🚀 LISTEN FOR TRIP NOTIFICATIONS
  void _listenForTripNotifications() {
    _notificationSubscription = _sessionManager.wsMessageStream.listen(
      (message) {
        print("🔔 Navbar: Received WebSocket message: $message");
        if (message['type'] == 'notification' && message['data'] != null) {
          final data = message['data'] as Map<String, dynamic>;
          _handleNotificationData(data);
        }
      },
      onError: (error) {
        print("❌ Navbar: WebSocket error: $error");
      },
    );
  }

  // NOTIFICATION DATA
  void _handleNotificationData(Map<String, dynamic> data) {
    print("🔔 Navbar: Processing notification data: $data");
    // NEW TRIP ACCEPTED - ADD TO LIST
    if (data['trip_id'] != null &&
        data['chat_room_id'] != null &&
        data['rider_username'] != null) {
      final tripId = data['trip_id'].toString();
      final existingIndex = activeTrips.indexWhere(
        (trip) => trip.tripId == tripId,
      );
      if (existingIndex == -1) {
        // Add new trip
        final newTrip = ActiveTrip(
          tripId: tripId,
          chatRoomId: data['chat_room_id'].toString(),
          riderName: data['rider_username'],
          riderId: data['rider_id'] ?? 0,
          bikeName: data['bike_name'] ?? 'Bike',
          startTime: DateTime.now(),
        );
        setState(() {
          activeTrips.add(newTrip);
        });
        print(
          "🎉 Navbar: New trip added! Total active trips: ${activeTrips.length}",
        );
        print("🎉 Trip: ${newTrip.toString()}");
        _showTripAcceptedNotification(newTrip);
        _autoNavigateToChat();
      } else {
        print("🔄 Navbar: Trip already exists, updating...");
      }
    }
    // TRIP ENDED - REMOVE FROM LIST AND NAVIGATE AWAY
    else if (data['trip_id'] != null &&
        (data['trip_status'] == 'completed' ||
            data['trip_status'] == 'canceled' ||
            data['trip_status'] == 'cancelled' ||
            data['action'] == 'trip_ended')) {
      final tripId = data['trip_id'].toString();
      final removedTrip = activeTrips
          .where((trip) => trip.tripId == tripId)
          .firstOrNull;
      print(
        "🔚 Navbar: Trip $tripId ended. Current trips: ${activeTrips.length}",
      );
      final bool wasViewingSingleChat =
          activeTrips.length == 1 && selectedIndex >= 3;

      setState(() {
        activeTrips.removeWhere((trip) => trip.tripId == tripId);
        // ✅ IMMEDIATE NAVIGATION AWAY FROM CHAT
        if (activeTrips.isEmpty && selectedIndex >= 3) {
          print("🔄 Navbar: No more trips, navigating to dashboard");
          selectedIndex = 0;
        } else if (activeTrips.length == 1 && selectedIndex >= 3) {
          print("🔄 Navbar: Now single chat, staying on chat tab");
        }
      });

      print("🔚 Navbar: Trip ended. Remaining trips: ${activeTrips.length}");
      // ✅ SHOW NOTIFICATION
      if (removedTrip != null) {
        _showTripEndedNotification(removedTrip);
      }
      if (wasViewingSingleChat && activeTrips.isEmpty) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {});
          }
        });
      }
    }
  }

  // SHOW TRIP ACCEPTED NOTIFICATION
  void _showTripAcceptedNotification(ActiveTrip trip) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "🎉 ${trip.riderName} started trip on ${trip.bikeName}",
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: "Chat",
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              selectedIndex = _getChatTabIndex();
            });
          },
        ),
      ),
    );
  }

  // SHOW TRIP ENDED NOTIFICATION
  void _showTripEndedNotification(ActiveTrip trip) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 12),
            Text("Trip with ${trip.riderName} completed"),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // AUTO-NAVIGATE TO CHAT
  void _autoNavigateToChat() {
    if (activeTrips.isEmpty) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && activeTrips.isNotEmpty) {
        setState(() {
          selectedIndex = _getChatTabIndex();
        });
      }
    });
  }

  // 🚀 GET CHAT TAB INDEX
  int _getChatTabIndex() {
    return activeTrips.isNotEmpty ? 3 : 0;
  }

  // ✅ FIXED: SCREENS LIST WITH EXPLICIT TYPING
  List<Widget> get currentScreens {
    // ✅ Create list with explicit Widget typing
    final List<Widget> screens = <Widget>[
      const OwnerAccountPage(),
      const Rides_page(),
      Account_page(user: currentUser), // ✅ This should work now
    ];

    // ✅ Add chat screen if there are active trips
    if (activeTrips.isNotEmpty) {
      final chatScreen = _buildChatScreen();
      if (chatScreen != null) {
        screens.add(chatScreen);
      }
    }

    return screens;
  }

  // ✅ FIXED: BUILD CHAT SCREEN WITH NULL SAFETY
  Widget? _buildChatScreen() {
    // ✅ SAFETY CHECK: If no active trips, return null
    if (activeTrips.isEmpty) {
      print("⚠️ Navbar: No active trips, returning null");
      return null;
    }

    if (activeTrips.length == 1) {
      // Single chat - go directly to ChatPage
      final trip = activeTrips.first;
      print("📱 Navbar: Building single ChatPage for trip ${trip.tripId}");

      return ChatPage(
        key: ValueKey(trip.tripId),
        tripId: trip.tripId,
        bikeOwnerName: trip.riderName,
        bikeOwnerId: trip.riderId,
      );
    } else {
      // Multiple chats - show ChatListPage
      print("📱 Navbar: Building ChatListPage for ${activeTrips.length} trips");
      return _buildChatListPage();
    }
  }

  // BUILD CHAT LIST PAGE
  Widget _buildChatListPage() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Active Chats (${activeTrips.length})'),
        automaticallyImplyLeading: false,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: activeTrips.length,
        itemBuilder: (context, index) {
          final trip = activeTrips[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Stack(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(
                trip.riderName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bike: ${trip.bikeName}'),
                  Text(
                    'Started: ${_formatTime(trip.startTime)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
              trailing: const Icon(Icons.chat_bubble, color: Colors.blue),
              onTap: () {
                // Navigate to specific chat
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatPage(
                      tripId: trip.tripId,
                      bikeOwnerName: trip.riderName,
                      bikeOwnerId: trip.riderId,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // FORMAT TIME
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }

  // 🚀 NAVIGATION DESTINATIONS
  List<NavigationDestination> get currentDestinations {
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.dashboard),
        label: "Dashboard",
      ),
      const NavigationDestination(
        icon: Icon(Icons.bike_scooter),
        label: "Rides",
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_2_rounded),
        label: "Profile",
      ),
    ];

    // ✅ ONLY ADD CHAT TAB IF THERE ARE ACTIVE TRIPS
    if (activeTrips.isNotEmpty) {
      destinations.add(
        NavigationDestination(
          icon: Stack(
            children: [
              const Icon(Icons.chat),
              // CHAT COUNT BADGE
              if (activeTrips.length > 1)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${activeTrips.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          label: activeTrips.length == 1 ? "Chat" : "Chats",
        ),
      );
    }

    return destinations;
  }

  @override
  Widget build(BuildContext context) {
    final screens = currentScreens;
    final destinations = currentDestinations;

    // ✅ ENSURE SELECTED INDEX IS VALID
    if (selectedIndex >= screens.length) {
      selectedIndex = 0;
    }

    print(
      "🔄 Navbar Build: ${activeTrips.length} trips, index: $selectedIndex",
    );

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          print("🔄 Navbar: Tab selected: $index");
          if (index < destinations.length) {
            setState(() {
              selectedIndex = index;
            });
          }
        },
        destinations: destinations,

        elevation: 8,
        height: 80,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
