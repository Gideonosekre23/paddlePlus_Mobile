import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../Apiendpoints/models/Ride_models.dart';
import '../Apiendpoints/apiservices/Ride_api_service.dart';

class Rides_page extends StatefulWidget {
  const Rides_page({super.key});

  @override
  State<Rides_page> createState() => _RidesPageState();
}

class _RidesPageState extends State<Rides_page> {
  List<OwnerTrip> ownerRides = [];
  OwnerInfo? ownerInfo;
  bool _isLoading = true;
  String? _errorMessage;

  String selectedFilter = 'All';
  final List<String> filterOptions = [
    'All',
    'Today',
    'This Week',
    'This Month',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _loadOwnerTrips();
  }

  /// Load owner trips from API
  Future<void> _loadOwnerTrips() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await OwnerTripsApiService.getOwnerTrips();

      if (response.success && response.data != null) {
        setState(() {
          ownerRides = response.data!.trips;
          ownerInfo = response.data!.owner;
          _isLoading = false;
        });
        print('✅ Loaded ${ownerRides.length} owner trips');
      } else {
        setState(() {
          _errorMessage = response.error ?? 'Failed to load trips';
          _isLoading = false;
        });
        print('❌ API Error: ${response.error}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: ${e.toString()}';
        _isLoading = false;
      });
      print('❌ Exception: $e');
    }
  }

  /// Filter trips based on selected filter
  List<OwnerTrip> get filteredRides {
    if (selectedFilter == 'All') {
      return ownerRides;
    }

    DateTime now = DateTime.now();

    switch (selectedFilter) {
      case 'Today':
        return ownerRides.where((ride) {
          if (ride.date == null) return false;
          return ride.date!.year == now.year &&
              ride.date!.month == now.month &&
              ride.date!.day == now.day;
        }).toList();

      case 'This Week':
        DateTime weekStart = now.subtract(Duration(days: now.weekday - 1));
        return ownerRides.where((ride) {
          if (ride.date == null) return false;
          return ride.date!.isAfter(
            weekStart.subtract(const Duration(days: 1)),
          );
        }).toList();

      case 'This Month':
        return ownerRides.where((ride) {
          if (ride.date == null) return false;
          return ride.date!.year == now.year && ride.date!.month == now.month;
        }).toList();

      case 'Completed':
        return ownerRides
            .where((ride) => ride.status.toLowerCase() == 'completed')
            .toList();

      case 'Cancelled':
        return ownerRides
            .where(
              (ride) =>
                  ride.status.toLowerCase() == 'canceled' ||
                  ride.status.toLowerCase() == 'cancelled',
            )
            .toList();

      default:
        return ownerRides;
    }
  }

  /// Refresh trips
  Future<void> _refreshTrips() async {
    await _loadOwnerTrips();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 118, 172, 198),
        automaticallyImplyLeading: false,
        title: const Text(
          'Bike Rentals',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (String value) {
              setState(() {
                selectedFilter = value;
              });
            },
            itemBuilder: (BuildContext context) {
              return filterOptions.map((String choice) {
                return PopupMenuItem<String>(
                  value: choice,
                  child: Row(
                    children: [
                      Icon(
                        selectedFilter == choice
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: selectedFilter == choice
                            ? const Color.fromARGB(255, 118, 172, 198)
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(choice),
                    ],
                  ),
                );
              }).toList();
            },
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: RefreshIndicator(
        onRefresh: _refreshTrips,
        color: const Color.fromARGB(255, 118, 172, 198),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color.fromARGB(255, 118, 172, 198),
            ),
            SizedBox(height: 16),
            Text(
              'Loading your bike rentals...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 80, color: Colors.red[300]),
              const SizedBox(height: 20),
              Text(
                'Oops! Something went wrong',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refreshTrips,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Try Again',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    List<OwnerTrip> filtered = filteredRides;

    return Column(
      children: [
        // Summary Statistics Card
        _buildSummaryCard(filtered),

        // Rides List
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState()
              : _buildRidesList(filtered),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(List<OwnerTrip> trips) {
    double totalEarnings = trips.fold(
      0.0,
      (sum, trip) => sum + (trip.ownerPayout ?? 0.0),
    );

    int completedTrips = trips
        .where((trip) => trip.status.toLowerCase() == 'completed')
        .length;

    double avgRating = 4.5;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color.fromARGB(255, 118, 172, 198),
            Color.fromARGB(255, 95, 158, 185),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 118, 172, 198).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                selectedFilter == 'All'
                    ? 'Overall Stats'
                    : '$selectedFilter Stats',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Total Rides',
                trips.length.toString(),
                Icons.bike_scooter,
                Colors.white,
              ),
              _buildStatItem(
                'Completed',
                completedTrips.toString(),
                Icons.check_circle_outline,
                Colors.white,
              ),
              _buildStatItem(
                'Earnings',
                '${totalEarnings.toStringAsFixed(0)} RON',
                Icons.account_balance_wallet,
                Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color.withOpacity(0.9)),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    String message;
    String subtitle;

    switch (selectedFilter) {
      case 'Today':
        message = 'No rides today';
        subtitle = 'Your daily rides will appear here';
        break;
      case 'This Week':
        message = 'No rides this week';
        subtitle = 'Your weekly rides will appear here';
        break;
      case 'This Month':
        message = 'No rides this month';
        subtitle = 'Your monthly rides will appear here';
        break;
      case 'Completed':
        message = 'No completed rides';
        subtitle = 'Completed rentals will appear here';
        break;
      case 'Cancelled':
        message = 'No cancelled rides';
        subtitle = 'Cancelled rentals will appear here';
        break;
      default:
        message = 'No rides yet';
        subtitle = 'Rentals on your bikes will appear here';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.pedal_bike, size: 64, color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  selectedFilter = 'All';
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('View All Rides'),
              style: TextButton.styleFrom(
                foregroundColor: const Color.fromARGB(255, 3, 46, 68),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRidesList(List<OwnerTrip> trips) {
    // Group trips by date
    Map<String, List<OwnerTrip>> groupedTrips = {};

    for (var trip in trips) {
      if (trip.date != null) {
        String dateKey = DateFormat('yyyy-MM-dd').format(trip.date!);
        if (!groupedTrips.containsKey(dateKey)) {
          groupedTrips[dateKey] = [];
        }
        groupedTrips[dateKey]!.add(trip);
      }
    }

    List<String> sortedDates = groupedTrips.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Most recent first

    if (groupedTrips.isEmpty) {
      // Handle trips without dates
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: trips.length,
        itemBuilder: (context, index) {
          return _buildRideCard(trips[index]);
        },
      );
    }

    // Continuing from where we left off...

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        String dateKey = sortedDates[index];
        List<OwnerTrip> dayTrips = groupedTrips[dateKey]!;
        DateTime date = DateTime.parse(dateKey);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Header
            Container(
              margin: const EdgeInsets.only(top: 16, bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 118, 172, 198),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatDateHeader(date),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${dayTrips.length} ride${dayTrips.length == 1 ? '' : 's'}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),

            // Trips for this date
            ...dayTrips.map((trip) => _buildRideCard(trip)),

            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildRideCard(OwnerTrip trip) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row - Bike name and Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(
                              255,
                              118,
                              172,
                              198,
                            ).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.pedal_bike,
                            color: Color.fromARGB(255, 118, 172, 198),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.bikeName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (trip.bikeInfo != null)
                                Text(
                                  trip.bikeInfo!.displayName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: trip.statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: trip.statusColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      trip.statusDisplayText,
                      style: TextStyle(
                        color: trip.statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Renter Information
              if (trip.renter != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[100]!, width: 1),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.blue[200],
                        child: Text(
                          trip.renter!.username.isNotEmpty
                              ? trip.renter!.username[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Renter: ${trip.renter!.username}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            if (trip.renter!.phone != null)
                              Text(
                                trip.renter!.phone!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.person, color: Colors.blue[600], size: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Location Information
              Row(
                children: [
                  Expanded(
                    child: _buildLocationInfo(
                      'From',
                      trip.startLocation.shortAddress,
                      Icons.location_on,
                      Colors.green,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: _buildLocationInfo(
                      'To',
                      trip.endLocation.shortAddress,
                      Icons.flag,
                      Colors.red,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Trip Details Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildDetailItem(
                    Icons.calendar_today,
                    'Date',
                    trip.formattedDate,
                    Colors.blue,
                  ),
                  _buildDetailItem(
                    Icons.route,
                    'Distance',
                    trip.formattedDistance,
                    Colors.orange,
                  ),
                  _buildDetailItem(
                    Icons.attach_money,
                    'Earned',
                    trip.formattedEarnings,
                    Colors.green,
                  ),
                ],
              ),

              // Payment Status (if available)
              if (trip.paymentStatus != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: trip.paymentStatus!.toLowerCase() == 'paid'
                        ? Colors.green[50]
                        : Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: trip.paymentStatus!.toLowerCase() == 'paid'
                          ? Colors.green[200]!
                          : Colors.orange[200]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trip.paymentStatus!.toLowerCase() == 'paid'
                            ? Icons.check_circle
                            : Icons.schedule,
                        color: trip.paymentStatus!.toLowerCase() == 'paid'
                            ? Colors.green[600]
                            : Colors.orange[600],
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Payment: ${trip.paymentStatus!.toUpperCase()}',
                        style: TextStyle(
                          color: trip.paymentStatus!.toLowerCase() == 'paid'
                              ? Colors.green[700]
                              : Colors.orange[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationInfo(
    String label,
    String address,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            address,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  String _formatDateHeader(DateTime date) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime cardDate = DateTime(date.year, date.month, date.day);

    int difference = today.difference(cardDate).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return DateFormat('EEEE').format(date); // Day name
    } else {
      return DateFormat('MMM dd, yyyy').format(date);
    }
  }
}
