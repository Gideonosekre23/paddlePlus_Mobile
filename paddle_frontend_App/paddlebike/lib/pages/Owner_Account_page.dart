import 'package:flutter/material.dart';
import 'package:paddlebike/Apiendpoints/apiservices/bike_api_service.dart';
import 'package:paddlebike/Apiendpoints/apiservices/Ride_api_service.dart';
import 'package:paddlebike/Apiendpoints/apiservices/image_utils.dart';
import 'package:paddlebike/Apiendpoints/apiservices/user_session_manager.dart';
import 'package:paddlebike/Apiendpoints/models/bike_model.dart';
import 'package:paddlebike/Apiendpoints/models/Ride_models.dart';
import 'package:paddlebike/Apiendpoints/models/auth_models.dart';
import 'package:paddlebike/pages/AddBikePage.dart';
import 'package:cached_network_image/cached_network_image.dart';

class OwnerAccountPage extends StatefulWidget {
  const OwnerAccountPage({super.key});

  @override
  State<OwnerAccountPage> createState() => _OwnerAccountPageState();
}

class _OwnerAccountPageState extends State<OwnerAccountPage> {
  final UserSessionManager _sessionManager = UserSessionManager();
  // Loading states
  bool _isLoadingBikes = false;
  bool _isLoadingTrips = false;
  User? _currentUser;

  // Data
  List<Bike> bikes = [];
  List<OwnerTrip> trips = [];
  OwnerInfo? ownerInfo;
  double weeklyEarnings = 0.0;

  // User session manager

  // Computed values - SIMPLIFIED
  double get totalEarnings => _currentUser?.total_earnings ?? 0.0;
  int get totalBikes => bikes.length;
  int get activeBikes => bikes.where((bike) => bike.isActive).length;
  int get availableBikes =>
      bikes.where((bike) => bike.isAvailable && bike.isActive).length;
  int get weeklyTrips {
    final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
    return trips
        .where((trip) => trip.date != null && trip.date!.isAfter(oneWeekAgo))
        .length;
  }

  @override
  void initState() {
    super.initState();
    _currentUser = _sessionManager.currentUser;
    _sessionManager.addListener(_onSessionChanged);
    _loadData();
  }

  void _onSessionChanged() {
    if (mounted && _sessionManager.currentUser != null) {
      setState(() {
        _currentUser = _sessionManager.currentUser;
      });
      print('👤 Session changed - user: ${_currentUser?.username}');
      print(
        '🖼️ Session changed - profile picture: ${_currentUser?.profilePicture}',
      );
    }
  }

  Future<void> _loadData() async {
    await Future.wait([_loadOwnerBikes(), _loadOwnerTrips()]);
  }

  Future<void> _loadOwnerBikes() async {
    if (!mounted) return;
    setState(() => _isLoadingBikes = true);

    try {
      final response = await BikeApiService.getOwnerBikes();
      if (mounted && response.success && response.data != null) {
        setState(() => bikes = response.data!.bikes);

        // Debug logging for battery data
        for (var bike in bikes) {
          print('🚲 Bike: ${bike.bikeName}');
          print('  - Direct battery: ${bike.batteryLevel}');
          print('  - Hardware battery: ${bike.hardware?.batteryLevel}');
          print('  - Is active: ${bike.isActive}');
          print('  - Is available: ${bike.isAvailable}');
        }
      }
    } catch (e) {
      print('❌ Error loading bikes: $e');
      if (mounted) _showError('Failed to load bikes');
    } finally {
      if (mounted) setState(() => _isLoadingBikes = false);
    }
  }

  Future<void> _loadOwnerTrips() async {
    if (!mounted) return;
    setState(() => _isLoadingTrips = true);

    try {
      final response = await OwnerTripsApiService.getOwnerTrips();
      if (mounted && response.success && response.data != null) {
        setState(() {
          trips = response.data!.trips;
          ownerInfo = response.data!.owner;
          _calculateWeeklyEarnings();
        });
        print('✅ Loaded ${trips.length} owner trips');
        print('💰 Total earnings from session: $totalEarnings RON');
      }
    } catch (e) {
      print('❌ Error loading trips: $e');
      if (mounted) _showError('Failed to load trips');
    } finally {
      if (mounted) setState(() => _isLoadingTrips = false);
    }
  }

  void _calculateWeeklyEarnings() {
    final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
    weeklyEarnings = trips
        .where((trip) => trip.date != null && trip.date!.isAfter(oneWeekAgo))
        .fold(0.0, (sum, trip) => sum + (trip.ownerPayout ?? 0.0));

    print('💰 Weekly earnings calculated: $weeklyEarnings RON');
    print('📅 Weekly trips: $weeklyTrips');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: const Color.fromARGB(255, 118, 172, 198),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildTotalEarningsCard(),
              const SizedBox(height: 16),
              _buildEarningsStatsRow(),
              const SizedBox(height: 16),
              _buildBikesSection(),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    final profileImageUrl = _getFullImageUrl(_currentUser?.profilePicture);

    print('👤 Current user: ${_currentUser?.username}');
    print('🖼️ Profile picture: ${_currentUser?.profilePicture}');
    print('🔗 Loading profile image: $profileImageUrl');

    return AppBar(
      backgroundColor: const Color.fromARGB(255, 118, 172, 198),
      foregroundColor: Colors.white,
      elevation: 0,
      title: Row(
        children: [
          // Username on the LEFT
          Expanded(
            child: Text(
              _currentUser?.username ?? 'Owner',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 18,
              ),
            ),
          ),
          // Profile Image on the RIGHT
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: ImageUtils.buildAvatar(
              profilePicture: _currentUser?.profilePicture,
              radius: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBikeImage(Bike bike, String bikeImageUrl) {
    return CachedNetworkImage(
      imageUrl: (bike.bikeImage?.isNotEmpty == true) ? bike.bikeImage! : '',
      width: 80,
      height: 80,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        width: 80,
        height: 80,
        color: const Color.fromARGB(255, 118, 172, 198).withOpacity(0.1),
        child: const Icon(
          Icons.pedal_bike,
          color: Color.fromARGB(255, 118, 172, 198),
          size: 40,
        ),
      ),
      errorWidget: (context, url, error) {
        print('❌ Image error for ${bike.bikeName}: $error');
        return Container(
          width: 80,
          height: 80,
          color: const Color.fromARGB(255, 118, 172, 198).withOpacity(0.1),
          child: const Icon(
            Icons.pedal_bike,
            color: Color.fromARGB(255, 118, 172, 198),
            size: 40,
          ),
        );
      },
    );
  }

  Widget _buildTotalEarningsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromARGB(255, 118, 172, 198),
            Color.fromARGB(255, 95, 158, 185),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text(
                'Total Earnings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${totalEarnings.toStringAsFixed(2)} RON',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showWithdrawDialog,
              icon: const Icon(Icons.monetization_on),
              label: const Text('Withdraw Earnings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color.fromARGB(255, 118, 172, 198),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Weekly Earnings',
            _isLoadingTrips
                ? '...'
                : '${weeklyEarnings.toStringAsFixed(2)} RON',
            Icons.trending_up,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Weekly Trips',
            _isLoadingTrips ? '...' : weeklyTrips.toString(),
            Icons.directions_bike,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Active Bikes',
            _isLoadingBikes ? '...' : activeBikes.toString(),
            Icons.pedal_bike,
            const Color.fromARGB(255, 118, 172, 198),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: title.contains('RON') ? 14 : 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBikesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBikesHeader(),
        const SizedBox(height: 16),
        _buildBikesList(),
      ],
    );
  }

  Widget _buildBikesHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Your Bikes',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddBikePage()),
          ).then((_) => _loadOwnerBikes()),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Bike'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 118, 172, 198),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBikesList() {
    if (_isLoadingBikes) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: Color.fromARGB(255, 118, 172, 198),
          ),
        ),
      );
    }

    if (bikes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.pedal_bike, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No bikes yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first bike to start earning money!',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddBikePage()),
              ).then((_) => _loadOwnerBikes()),
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Bike'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Column(children: bikes.map((bike) => _buildBikeCard(bike)).toList());
  }

  Widget _buildBikeCard(Bike bike) {
    final batteryLevel = _getBatteryLevel(bike);
    final batteryColor = _getBatteryColor(batteryLevel);
    final batteryIcon = _getBatteryIcon(batteryLevel);
    final bikeImageUrl = _getFullImageUrl(bike.bikeImage);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ FIX: Bike Header Row with better layout
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start, // ✅ FIX: Align to start
            children: [
              // ✅ FIX: Bike Image with better error handling
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color.fromARGB(
                    255,
                    118,
                    172,
                    198,
                  ).withOpacity(0.1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildBikeImage(bike, bikeImageUrl),
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bike Name
                    Text(
                      bike.bikeName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1, // ✅ FIX: Prevent overflow
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    Text(
                      '${bike.brand} ${bike.model}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (bike.color != null && bike.color!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Color: ${bike.color}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),

                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(batteryIcon, size: 18, color: batteryColor),
                        const SizedBox(width: 6),
                        Text(
                          '$batteryLevel%',
                          style: TextStyle(
                            color: batteryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: batteryLevel / 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: batteryColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [_buildBikeStatusBadge(bike)],
              ),
            ],
          ),

          if (bike.bikeAddress != null && bike.bikeAddress!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    bike.bikeAddress!,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => _showRemoveBikeDialog(bike),
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Remove', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                flex: 3,
                child: !bike.isActive
                    ? ElevatedButton.icon(
                        onPressed: () => _activateBike(bike),
                        icon: const Icon(Icons.power_settings_new, size: 16),
                        label: const Text(
                          'Activate',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () => _toggleBikeAvailability(bike),
                        icon: Icon(
                          bike.isAvailable
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 16,
                        ),
                        label: Text(
                          bike.isAvailable ? 'Hide' : 'Show',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: bike.isAvailable
                              ? Colors.red
                              : Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBikeStatusBadge(Bike bike) {
    Color color;
    String text;
    IconData icon;

    if (!bike.isActive) {
      color = Colors.orange;
      text = "Setup";
      icon = Icons.settings;
    } else if (!bike.isAvailable) {
      color = Colors.red;
      text = "Hidden";
      icon = Icons.visibility_off;
    } else {
      color = Colors.green;
      text = "Live";
      icon = Icons.visibility;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getFullImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';

    // If already a full URL, return as is
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }

    // Convert relative path to full URL
    const String baseUrl = 'http://10.0.2.2:8000';

    if (imagePath.startsWith('/')) {
      final fullUrl = '$baseUrl$imagePath';
      print('🔄 Converting to full URL: $fullUrl');
      return fullUrl;
    } else {
      final fullUrl = '$baseUrl/$imagePath';
      print('🔄 Converting to full URL: $fullUrl');
      return fullUrl;
    }
  }

  // Get actual battery level from API data - FIXED
  int _getBatteryLevel(Bike bike) {
    int? batteryLevel;

    // Priority 1: Try hardware battery level first (most accurate)
    if (bike.hardware?.batteryLevel != null) {
      batteryLevel = bike.hardware!.batteryLevel!;
      print('🔋 Using hardware battery: $batteryLevel% for ${bike.bikeName}');
    }
    // Priority 2: Try bike's direct battery level
    else if (bike.batteryLevel != null) {
      batteryLevel = bike.batteryLevel!;
      print('🔋 Using bike battery: $batteryLevel% for ${bike.bikeName}');
    }
    // Priority 3: Default to 0 if no battery data
    else {
      batteryLevel = 0;
      print('⚠️ No battery data for ${bike.bikeName}, using 0%');
    }

    // Ensure battery level is within valid range (0-100)
    return batteryLevel.clamp(0, 100);
  }

  Color _getBatteryColor(int batteryLevel) {
    if (batteryLevel >= 60) {
      return Colors.green;
    } else if (batteryLevel >= 30) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  IconData _getBatteryIcon(int batteryLevel) {
    if (batteryLevel >= 90) {
      return Icons.battery_full;
    } else if (batteryLevel >= 75) {
      return Icons.battery_6_bar;
    } else if (batteryLevel >= 50) {
      return Icons.battery_4_bar;
    } else if (batteryLevel >= 25) {
      return Icons.battery_2_bar;
    } else if (batteryLevel > 0) {
      return Icons.battery_1_bar;
    } else {
      return Icons.battery_0_bar;
    }
  }

  Future<void> _activateBike(Bike bike) async {
    final serialNumber = await _showActivationDialog();
    if (serialNumber == null || serialNumber.isEmpty) return;

    _showLoading('Activating bike...');

    try {
      final response = await BikeApiService.activateBike(
        bike.id,
        ActivateBikeRequest(serialNumber: serialNumber),
      );

      Navigator.of(context).pop(); // Close loading dialog

      if (response.success) {
        _showSuccess('Bike activated successfully!');
        await _loadOwnerBikes(); // Refresh bikes list
      } else {
        _showError(response.error ?? 'Failed to activate bike');
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _showError('Error activating bike: ${e.toString()}');
    }
  }

  Future<void> _toggleBikeAvailability(Bike bike) async {
    _showLoading('Updating bike availability...');

    try {
      final response = await BikeApiService.toggleBikeAvailability(bike.id);

      Navigator.of(context).pop(); // Close loading dialog

      if (response.success) {
        final message = bike.isAvailable
            ? 'Bike is now hidden from riders'
            : 'Bike is now available for riders';
        _showSuccess(message);
        await _loadOwnerBikes(); // Refresh bikes list
      } else {
        _showError(response.error ?? 'Failed to update bike availability');
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _showError('Error updating bike: ${e.toString()}');
    }
  }

  Future<void> _removeBike(Bike bike) async {
    _showLoading('Removing bike...');

    try {
      final response = await BikeApiService.removeBike(bike.id);

      Navigator.of(context).pop();

      if (response.success) {
        _showSuccess('Bike removed successfully!');
        await _loadOwnerBikes();
        await _loadOwnerTrips();
      } else {
        _showError(response.error ?? 'Failed to remove bike');
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showError('Error removing bike: ${e.toString()}');
    }
  }

  Future<String?> _showActivationDialog() async {
    String serialNumber = '';

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.power_settings_new, color: Colors.orange),
            SizedBox(width: 8),
            Text('Activate Bike'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the hardware serial number:'),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => serialNumber = value.trim(),
              decoration: const InputDecoration(
                labelText: 'Serial Number',
                hintText: 'e.g., BH001234',
                prefixIcon: Icon(Icons.qr_code),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can find the serial number on the bike\'s QR code sticker.',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (serialNumber.isNotEmpty) {
                Navigator.of(context).pop(serialNumber);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
  }

  void _showRemoveBikeDialog(Bike bike) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Remove Bike'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to remove "${bike.bikeName}"?'),
            const SizedBox(height: 8),
            Text(
              '${bike.brand} ${bike.model}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This action will:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Remove the bike from your account',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    '• Unassign any connected hardware',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text('• Cannot be undone', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeBike(bike);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.green),
            SizedBox(width: 8),
            Text('Withdraw Earnings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Column(
                children: [
                  const Text(
                    'Available Balance',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${totalEarnings.toStringAsFixed(2)} RON',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Withdrawal Information',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Withdrawal feature is coming soon! Contact support for manual withdrawals.',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showInfo(
                'Contact support at support@paddleplus.com for withdrawals',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Contact Support'),
          ),
        ],
      ),
    );
  }

  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(
              color: Color.fromARGB(255, 118, 172, 198),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _sessionManager.removeListener(_onSessionChanged);
    super.dispose();
  }
}
