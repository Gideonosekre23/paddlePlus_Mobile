import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:paddleapp/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddleapp/Apiendpoints/models/auth_models.dart';
import 'package:paddleapp/constants/Navbar.dart';
import 'package:paddleapp/Apiendpoints/apiservices/Ride_api_service.dart';
import 'package:paddleapp/Apiendpoints/models/Ride_models.dart';

class Rides_page extends StatefulWidget {
  const Rides_page({super.key});

  @override
  State<Rides_page> createState() => _RidesPageState();
}

class _RidesPageState extends State<Rides_page> {
  List<UserTrip> _userTrips = [];
  bool _isLoading = true;
  bool _isRefreshing = false; // ✅ Add refresh state
  String? _errorMessage;
  final UserSessionManager _sessionManager = UserSessionManager();

  @override
  void initState() {
    super.initState();
    _fetchUserTrips();
  }

  // ✅ UPDATED: Support both initial loading and refresh
  Future<void> _fetchUserTrips({bool isRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      if (isRefresh) {
        _isRefreshing = true;
        _errorMessage = null; // Clear errors on refresh
      } else {
        _isLoading = true;
        _errorMessage = null;
      }
    });

    try {
      final response = await RideApiService.getUserTrips();

      if (response.success && response.data != null) {
        if (!mounted) return;
        setState(() {
          _userTrips = response.data!.trips;
          _isLoading = false;
          _isRefreshing = false;
        });

        // ✅ Show success message on manual refresh
        if (isRefresh) {
          _showSuccessSnackbar('Rides updated successfully!');
        }
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = response.error ?? "Failed to load trips.";
          _isLoading = false;
          _isRefreshing = false;
        });

        // ✅ Show error message on refresh failure
        if (isRefresh) {
          _showErrorSnackbar(_errorMessage!);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final errorMsg = "An error occurred: ${e.toString()}";
      setState(() {
        _errorMessage = errorMsg;
        _isLoading = false;
        _isRefreshing = false;
      });

      // ✅ Show error message on refresh failure
      if (isRefresh) {
        _showErrorSnackbar(errorMsg);
      }
    }
  }

  // ✅ REFRESH HANDLER
  Future<void> _onRefresh() async {
    await _fetchUserTrips(isRefresh: true);
  }

  // ✅ SUCCESS SNACKBAR
  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ✅ ERROR SNACKBAR
  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () => _fetchUserTrips(isRefresh: true),
        ),
      ),
    );
  }

  Map<String, List<UserTrip>> _groupTripsByDate(List<UserTrip> trips) {
    final Map<String, List<UserTrip>> grouped = {};
    for (var trip in trips) {
      if (trip.date == null) {
        final key = "Unknown Date";
        grouped.putIfAbsent(key, () => []).add(trip);
        continue;
      }
      try {
        final dateTime = DateTime.parse(trip.date!);
        final dateKey = _formatDateHeader(dateTime);
        grouped.putIfAbsent(dateKey, () => []).add(trip);
      } catch (e) {
        print("Error parsing date for trip ${trip.id}: ${trip.date} - $e");
        final key = "Invalid Date";
        grouped.putIfAbsent(key, () => []).add(trip);
      }
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Rides'),
        backgroundColor: const Color.fromARGB(255, 118, 172, 198),
        elevation: 0,
        // ✅ ADD REFRESH BUTTON IN APP BAR
        actions: [
          IconButton(
            onPressed: _isRefreshing ? null : _onRefresh,
            icon:
                _isRefreshing
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.refresh),
            tooltip: 'Refresh rides',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? _buildErrorState()
              : _userTrips.isEmpty
              ? _buildEmptyState()
              : _buildRefreshableContent(), // ✅ Wrap content with RefreshIndicator
    );
  }

  // ✅ REFRESHABLE CONTENT WITH PULL-TO-REFRESH
  Widget _buildRefreshableContent() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color.fromARGB(255, 118, 172, 198),
      backgroundColor: Colors.white,
      displacement: 40.0,
      child: _buildGroupedTripList(),
    );
  }

  // ✅ IMPROVED ERROR STATE WITH REFRESH OPTION
  Widget _buildErrorState() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height - 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 80, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isRefreshing ? null : () => _fetchUserTrips(),
                      icon:
                          _isRefreshing
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.refresh),
                      label: Text(_isRefreshing ? 'Retrying...' : 'Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          118,
                          172,
                          198,
                        ),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Pull down to refresh',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ IMPROVED EMPTY STATE WITH REFRESH OPTION
  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height - 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.directions_bike_outlined,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                const Text(
                  'No rides yet!',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start your first bike ride to see it here.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isRefreshing ? null : _onRefresh,
                  icon:
                      _isRefreshing
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.refresh),
                  label: Text(_isRefreshing ? 'Checking...' : 'Check Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Pull down to refresh',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupedTripList() {
    final groupedTrips = _groupTripsByDate(_userTrips);
    final dateKeys = groupedTrips.keys.toList();
    final DateFormat fullDateFormat = DateFormat('EEEE, MMMM d, yyyy');

    int getSortPriority(String dateKey) {
      if (dateKey == 'Today') return 0;
      if (dateKey == 'Yesterday') return 1;
      try {
        fullDateFormat.parseStrict(dateKey);
        return 2;
      } catch (e) {
        return 3;
      }
    }

    dateKeys.sort((a, b) {
      int priorityA = getSortPriority(a);
      int priorityB = getSortPriority(b);
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }
      if (priorityA == 2) {
        try {
          DateTime dateA = fullDateFormat.parseStrict(a);
          DateTime dateB = fullDateFormat.parseStrict(b);
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      }
      return 0;
    });

    return ListView.builder(
      // ✅ ENSURE SCROLL PHYSICS WORK WITH REFRESH
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: dateKeys.length,
      itemBuilder: (context, index) {
        final dateKey = dateKeys[index];
        final tripsOnDate = groupedTrips[dateKey]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Text(
                dateKey,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 70, 70, 70),
                ),
              ),
            ),
            ...tripsOnDate.map((trip) => _buildTripCard(context, trip)),
            if (index < dateKeys.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        );
      },
    );
  }

  Future<void> _showRatingDialog(UserTrip trip) async {
    int selectedRating = 0;
    final reviewController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Rate your ride on ${trip.bikeName}'),
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
                    onPressed: () => setDialogState(() => selectedRating = star),
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
                      final response = await RideApiService.rateTrip(
                        trip.id.toString(),
                        RateTripRequest(
                          rating: selectedRating,
                          review: reviewController.text.trim().isEmpty
                              ? null
                              : reviewController.text.trim(),
                        ),
                      );
                      if (mounted) {
                        if (response.success) {
                          _showSuccessSnackbar('Thanks for your rating!');
                          _fetchUserTrips(isRefresh: true);
                        } else {
                          _showErrorSnackbar(
                              response.error ?? 'Failed to submit rating');
                        }
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

  Widget _buildTripCard(BuildContext context, UserTrip trip) {
    String bikeDisplayName = trip.bikeName;
    String startAddress = trip.startLocation.address;
    String endAddress = trip.endLocation.address;
    final isCompleted = trip.status.toLowerCase() == 'completed';
    final needsRating = isCompleted && trip.riderRating == null;

    return Card(
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_bike,
                  color: Theme.of(context).primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    bikeDisplayName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  trip.status,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isCompleted
                        ? Colors.green[700]
                        : trip.status.toLowerCase() == 'canceled'
                            ? Colors.red[700]
                            : Colors.orange[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildLocationRow(Icons.trip_origin, startAddress, "From"),
            const SizedBox(height: 6),
            _buildLocationRow(Icons.location_on, endAddress, "To"),
            // Show existing rating if present
            if (trip.riderRating != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < trip.riderRating! ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Your rating: ${trip.riderRating}/5',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  trip.price != null
                      ? '€${trip.price!.toStringAsFixed(2)}'
                      : 'Price N/A',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 118, 172, 198),
                  ),
                ),
                Row(
                  children: [
                    if (needsRating) ...[
                      ElevatedButton.icon(
                        onPressed: () => _showRatingDialog(trip),
                        icon: const Icon(Icons.star, size: 16),
                        label: const Text('Rate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton(
                      onPressed: () {
                        final User? currentUser = _sessionManager.currentUser;
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => Navbar(
                              initialDestination: trip.endLocation.address,
                              initialDestinationLat: trip.endLocation.latitude,
                              initialDestinationLng: trip.endLocation.longitude,
                              tripActive: false,
                              user: currentUser,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 31, 88, 31),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Ride Again'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String address, String prefix) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey[600], size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "$prefix: $address",
            style: TextStyle(fontSize: 14, color: Colors.grey[800]),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  String _formatDateHeader(DateTime date) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = today.subtract(const Duration(days: 1));

    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      return 'Today';
    } else if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMMM d, yyyy').format(date);
    }
  }
}
