import 'package:flutter/material.dart';
import 'package:paddlebike/Apiendpoints/apiservices/Riderequest_api_services.dart';
import 'package:paddlebike/Apiendpoints/models/api_response.dart';

import 'package:paddlebike/main.dart';

class GlobalNotificationOverlay {
  static final GlobalNotificationOverlay _instance =
      GlobalNotificationOverlay._internal();
  factory GlobalNotificationOverlay() => _instance;
  GlobalNotificationOverlay._internal();

  OverlayEntry? _currentOverlay;

  void showRideRequestCard(BuildContext context, Map<String, dynamic> data) {
    print("🔔 GlobalNotificationOverlay: Showing ride request card");
    _removeCurrentOverlay();

    try {
      final navigatorState = navigatorKey.currentState;
      if (navigatorState == null) {
        print("❌ Navigator state is null");
        return;
      }

      final overlay = navigatorState.overlay;
      if (overlay == null) {
        print("❌ Overlay is null");
        return;
      }

      _currentOverlay = OverlayEntry(
        builder: (context) => _buildRideRequestCard(context, data),
      );

      overlay.insert(_currentOverlay!);
      print("✅ Ride request card shown successfully");

      // Auto-dismiss after 30 seconds
      Future.delayed(const Duration(seconds: 30), () {
        _removeCurrentOverlay();
      });
    } catch (e, stackTrace) {
      print("❌ Error showing ride request card: $e");
      print("❌ Stack trace: $stackTrace");
    }
  }

  void showRideCancelledCard(BuildContext context, Map<String, dynamic> data) {
    print("🔔 GlobalNotificationOverlay: Showing ride cancelled card");
    _removeCurrentOverlay();

    try {
      // ✅ Use global navigator key instead of context
      final navigatorState = navigatorKey.currentState;
      if (navigatorState == null) {
        print("❌ Navigator state is null");
        return;
      }

      final overlay = navigatorState.overlay;
      if (overlay == null) {
        print("❌ Overlay is null");
        return;
      }

      _currentOverlay = OverlayEntry(
        builder: (context) => _buildRideCancelledCard(context, data),
      );

      overlay.insert(_currentOverlay!);
      print("✅ Ride cancelled card shown successfully");

      // Auto-dismiss after 10 seconds
      Future.delayed(const Duration(seconds: 10), () {
        _removeCurrentOverlay();
      });
    } catch (e, stackTrace) {
      print("❌ Error showing ride cancelled card: $e");
      print("❌ Stack trace: $stackTrace");
    }
  }

  void _removeCurrentOverlay() {
    try {
      if (_currentOverlay != null && _currentOverlay!.mounted) {
        _currentOverlay!.remove();
        _currentOverlay = null;
        print("✅ Overlay removed successfully");
      }
    } catch (e) {
      print("❌ Error removing overlay: $e");
      _currentOverlay = null; // Reset anyway
    }
  }

  // ✅ NEW: Accept ride request
  Future<void> _acceptRideRequest(String tempRequestId) async {
    print("🚴‍♂️ Accepting ride request: $tempRequestId");

    try {
      final ApiResponse<Map<String, dynamic>> response =
          await RideRequestApiService.acceptRideRequest(tempRequestId);

      if (response.success) {
        print("✅ Ride request accepted successfully");
        _showSuccessSnackbar(
          "✅ Ride request accepted! Rider has been notified.",
        );
        _removeCurrentOverlay();
      } else {
        print("❌ Failed to accept ride request: ${response.error}");
        _showErrorSnackbar(
          "❌ Failed to accept ride: ${response.error ?? 'Unknown error'}",
        );
      }
    } catch (e) {
      print("❌ Error accepting ride request: $e");
      _showErrorSnackbar("❌ Error accepting ride request. Please try again.");
    }
  }

  // ✅ NEW: Decline ride request
  Future<void> _declineRideRequest(String tempRequestId) async {
    print("❌ Declining ride request: $tempRequestId");

    try {
      final ApiResponse<Map<String, dynamic>> response =
          await RideRequestApiService.declineRideRequest(tempRequestId);

      if (response.success) {
        print("✅ Ride request declined successfully");
        _showSuccessSnackbar(
          "✅ Ride request declined. Rider has been notified.",
        );
        _removeCurrentOverlay();
      } else {
        print("❌ Failed to decline ride request: ${response.error}");
        _showErrorSnackbar(
          "❌ Failed to decline ride: ${response.error ?? 'Unknown error'}",
        );
      }
    } catch (e) {
      print("❌ Error declining ride request: $e");
      _showErrorSnackbar("❌ Error declining ride request. Please try again.");
    }
  }

  // ✅ NEW: Show success snackbar
  void _showSuccessSnackbar(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ✅ NEW: Show error snackbar
  void _showErrorSnackbar(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildRideRequestCard(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    // ✅ Extract temp_request_id for API calls
    final tempRequestId = data['temp_request_id'] as String?;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.notifications_active,
                    color: Colors.green,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '🚴‍♂️ NEW RIDE REQUEST',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeCurrentOverlay(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${data['rider_username'] ?? 'Someone'} wants to rent your ${data['bike_name'] ?? 'bike'}',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      'Your Earnings: ${data['your_earnings'] ?? 'N/A'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    Text(
                      'Distance: ${data['trip_distance'] ?? 'N/A'}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '💳 Payment Already Completed!',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),

              // ✅ Show expire time
              if (data['expires_in_minutes'] != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '⏰ Expires in ${data['expires_in_minutes']} minutes',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      // ✅ Call accept API
                      onPressed: tempRequestId != null
                          ? () => _acceptRideRequest(tempRequestId)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'ACCEPT RIDE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      // ✅ Call decline API
                      onPressed: tempRequestId != null
                          ? () => _declineRideRequest(tempRequestId)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'DECLINE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ✅ Show temp_request_id for debugging (remove in production)
              if (tempRequestId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Request ID: ${tempRequestId.substring(0, 8)}...',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRideCancelledCard(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.cancel, color: Colors.orange, size: 30),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '❌ RIDE CANCELLED',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeCurrentOverlay(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${data['rider_username'] ?? 'Someone'} cancelled their ride request for ${data['bike_name'] ?? 'your bike'}',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${data['note'] ?? 'Your bike is now available for other requests'}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _removeCurrentOverlay(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
