import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart' as location_service;
import 'package:geocoding/geocoding.dart';
import 'dart:io';
import 'dart:convert';
import 'package:paddlebike/Apiendpoints/apiservices/bike_api_service.dart';
import 'package:paddlebike/Apiendpoints/models/bike_model.dart';
import 'package:paddlebike/Apiendpoints/models/api_response.dart';

class AddBikePage extends StatefulWidget {
  const AddBikePage({super.key});

  @override
  State<AddBikePage> createState() => _AddBikePageState();
}

class _AddBikePageState extends State<AddBikePage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for form fields
  final TextEditingController _bikeNameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String _selectedSize = 'Medium';
  bool _isLoading = false;
  bool _isGettingLocation = false;

  // Image and location data
  File? _selectedImage;
  String? _base64Image;
  double? _latitude;
  double? _longitude;
  String? _bikeAddress;

  final List<String> _bikeSizes = ['Small', 'Medium', 'Large', 'Extra Large'];
  final ImagePicker _imagePicker = ImagePicker();
  final location_service.Location _location = location_service.Location();

  @override
  void dispose() {
    _bikeNameController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _yearController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 118, 172, 198),
        title: const Text(
          'Add New Bike',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Hardware Activation Required',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'After adding your bike details, we\'ll send you the hardware kit for activation. Your bike will be available for rent once activated.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ✅ ADD: Bike Image Section
                _buildImageSection(),
                const SizedBox(height: 16),

                // Bike Name
                _buildTextField(
                  controller: _bikeNameController,
                  label: 'Bike Name',
                  hint: 'e.g., City Cruiser',
                  icon: Icons.pedal_bike,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a bike name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Brand
                _buildTextField(
                  controller: _brandController,
                  label: 'Brand',
                  hint: 'e.g., Trek, Giant, Specialized',
                  icon: Icons.branding_watermark,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the bike brand';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Model
                _buildTextField(
                  controller: _modelController,
                  label: 'Model',
                  hint: 'e.g., FX 3, Escape 3, Sirrus',
                  icon: Icons.model_training,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the bike model';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Color
                _buildTextField(
                  controller: _colorController,
                  label: 'Color',
                  hint: 'e.g., Red, Blue, Black',
                  icon: Icons.palette,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the bike color';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Size Dropdown
                _buildSizeDropdown(),
                const SizedBox(height: 16),

                // Year
                _buildTextField(
                  controller: _yearController,
                  label: 'Year',
                  hint: 'e.g., 2023',
                  icon: Icons.calendar_today,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the year';
                    }
                    int? year = int.tryParse(value);
                    if (year == null ||
                        year < 1990 ||
                        year > DateTime.now().year + 1) {
                      return 'Please enter a valid year';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // ✅ ADD: Location Section
                _buildLocationSection(),
                const SizedBox(height: 16),

                // Description
                _buildTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  hint: 'Describe your bike (features, condition, etc.)',
                  icon: Icons.description,
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitBike,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 118, 172, 198),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Add Bike',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Info Footer
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hardware kit will be shipped to your registered address within 3-5 business days.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ NEW: Build image section
  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bike Image',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey.shade50,
          ),
          child: _selectedImage != null
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _selectedImage!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedImage = null;
                            _base64Image = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : InkWell(
                  onTap: _showImagePicker,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 50,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tap to add bike image',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Required',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ✅ NEW: Build location section
  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bike Location',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _addressController,
          decoration: InputDecoration(
            hintText: 'Enter bike address or use current location',
            prefixIcon: const Icon(Icons.location_on),
            suffixIcon: IconButton(
              onPressed: _isGettingLocation ? null : _getCurrentLocation,
              icon: _isGettingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color.fromARGB(255, 118, 172, 198),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          validator: (value) {
            if ((value == null || value.isEmpty) &&
                (_latitude == null || _longitude == null)) {
              return 'Please enter an address or use current location';
            }
            return null;
          },
        ),
        if (_latitude != null && _longitude != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Location: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ✅ NEW: Build size dropdown
  Widget _buildSizeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Size',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedSize,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.straighten),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color.fromARGB(255, 118, 172, 198),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          items: _bikeSizes.map((String size) {
            return DropdownMenuItem<String>(value: size, child: Text(size));
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedSize = newValue;
              });
            }
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please select a size';
            }
            return null;
          },
        ),
      ],
    );
  }

  // ✅ NEW: Build text field helper
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color.fromARGB(255, 118, 172, 198),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          validator: validator,
        ),
      ],
    );
  }

  // ✅ NEW: Show image picker bottom sheet
  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add Bike Image',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt,
                    color: Color.fromARGB(255, 118, 172, 198),
                  ),
                  title: const Text('Take Photo'),
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library,
                    color: Color.fromARGB(255, 118, 172, 198),
                  ),
                  title: const Text('Choose from Gallery'),
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✅ NEW: Pick image from camera or gallery
  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context); // Close bottom sheet

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        print("📷 Image picked: ${image.path}");
        setState(() {
          _selectedImage = File(image.path);
        });

        // Convert to base64 for API
        final bytes = await File(image.path).readAsBytes();
        setState(() {
          _base64Image = base64Encode(bytes);
        });

        print("📷 Base64 length: ${_base64Image?.length}");
        _showSuccessMessage("Bike image selected!");
      }
    } catch (e) {
      print("❌ Error selecting image: $e");
      _showErrorMessage("Error selecting image: ${e.toString()}");
    }
  }

  // ✅ NEW: Get current location
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
    });

    try {
      bool serviceEnabled;
      location_service.PermissionStatus permissionGranted; // ✅ FIX: Use alias
      location_service.LocationData locationData; // ✅ FIX: Use alias

      // Check if location services are enabled
      serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          _showErrorMessage(
            'Location services are disabled. Please enable them.',
          );
          return;
        }
      }

      // Check location permissions
      permissionGranted = await _location.hasPermission();
      if (permissionGranted == location_service.PermissionStatus.denied) {
        // ✅ FIX: Use alias
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != location_service.PermissionStatus.granted) {
          // ✅ FIX: Use alias
          _showErrorMessage(
            'Location permission is required to add bike location.',
          );
          return;
        }
      }

      // Get location
      locationData = await _location.getLocation();

      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _latitude = locationData.latitude!;
          _longitude = locationData.longitude!;
        });

        // Get address from coordinates
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            _latitude!,
            _longitude!,
          );

          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            String address = '';

            if (place.street != null && place.street!.isNotEmpty) {
              address += place.street!;
            }
            if (place.locality != null && place.locality!.isNotEmpty) {
              address += address.isEmpty
                  ? place.locality!
                  : ', ${place.locality!}';
            }
            if (place.administrativeArea != null &&
                place.administrativeArea!.isNotEmpty) {
              address += address.isEmpty
                  ? place.administrativeArea!
                  : ', ${place.administrativeArea!}';
            }
            if (place.country != null && place.country!.isNotEmpty) {
              address += address.isEmpty
                  ? place.country!
                  : ', ${place.country!}';
            }

            setState(() {
              _bikeAddress = address;
              _addressController.text = address;
            });
          }
        } catch (e) {
          print("❌ Error getting address: $e");
          setState(() {
            _bikeAddress =
                "Location: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}";
            _addressController.text = _bikeAddress!;
          });
        }

        _showSuccessMessage('Location obtained successfully!');
      }
    } catch (e) {
      print("❌ Error getting location: $e");
      _showErrorMessage('Error getting location: ${e.toString()}');
    } finally {
      setState(() {
        _isGettingLocation = false;
      });
    }
  }

  // ✅ NEW: Submit bike to API
  Future<void> _submitBike() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorMessage('Please fill in all required fields');
      return;
    }

    if (_selectedImage == null || _base64Image == null) {
      _showErrorMessage('Please add a bike image');
      return;
    }

    if (_latitude == null || _longitude == null) {
      _showErrorMessage('Please add bike location');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create AddBikeRequest
      final addBikeRequest = AddBikeRequest(
        bikeName: _bikeNameController.text.trim(),
        brand: _brandController.text.trim(),
        model: _modelController.text.trim(),
        color: _colorController.text.trim(),
        size: _selectedSize,
        year: int.parse(_yearController.text.trim()),
        latitude: _latitude!,
        longitude: _longitude!,
        bikeAddress: _addressController.text.trim(),
        description: _descriptionController.text.trim(),
        bikeImage: _base64Image, // ✅ FIX: Now this field exists
      );

      print("🔄 Submitting bike:");
      print("  - Name: ${addBikeRequest.bikeName}");
      print("  - Brand: ${addBikeRequest.brand}");
      print("  - Model: ${addBikeRequest.model}");
      print(
        "  - Location: ${addBikeRequest.latitude}, ${addBikeRequest.longitude}",
      );
      print("  - Has image: ${addBikeRequest.bikeImage != null}");

      // ✅ FIX: Use correct response type
      final ApiResponse<AddBikeResponse> response =
          await BikeApiService.addBike(addBikeRequest);

      print("📨 API Response:");
      print("  - Success: ${response.success}");
      print("  - Data: ${response.data}");
      print("  - Error: ${response.error}");

      if (response.success && response.data != null) {
        _showSuccessMessage(
          'Bike added successfully! Hardware kit will be shipped soon.',
        );

        // Clear form and go back after a delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pop(
              context,
              response.data,
            ); // Return the created bike response
          }
        });
      } else {
        _showErrorMessage(
          response.error ?? "Failed to add bike. Please try again.",
        );
      }
    } catch (e) {
      print("❌ Bike submission error: $e");
      _showErrorMessage("An unexpected error occurred. Please try again.");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ✅ NEW: Helper methods for showing messages
  void _showErrorMessage(String message) {
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
      ),
    );
  }

  void _showSuccessMessage(String message) {
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
}
