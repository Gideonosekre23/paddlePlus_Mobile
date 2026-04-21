import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_flutter/google_places_flutter.dart';

class SearchArea extends StatefulWidget {
  final String apiKey;
  final Function(LatLng) onLocationSelected;
  final Future<GoogleMapController>? mapController;
  final String hint;
  final Color? backgroundColor;
  final Color? shadowColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final TextEditingController? controller;

  const SearchArea({
    super.key,
    required this.apiKey,
    required this.onLocationSelected,
    this.mapController,
    this.hint = 'Search for a location',
    this.backgroundColor = Colors.white,
    this.shadowColor,
    this.borderRadius = 8.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
    this.controller,
  });

  @override
  State<SearchArea> createState() => _SearchAreaState();
}

class _SearchAreaState extends State<SearchArea> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Container(
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: [
            BoxShadow(
              color: widget.shadowColor ?? Colors.grey.withOpacity(0.5),
              spreadRadius: 2,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: GooglePlaceAutoCompleteTextField(
          textEditingController: _controller,
          googleAPIKey: widget.apiKey,
          inputDecoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 15,
            ),
          ),
          debounceTime: 800,
          countries: ['ro'],
          isLatLngRequired: true,
          getPlaceDetailWithLatLng: (prediction) {
            final lat = double.tryParse(prediction.lat ?? '');
            final lng = double.tryParse(prediction.lng ?? '');

            if (lat != null && lng != null) {
              final selectedLatLng = LatLng(lat, lng);
              widget.onLocationSelected(selectedLatLng);

              if (widget.mapController != null) {
                widget.mapController!.then((controller) {
                  controller.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(target: selectedLatLng, zoom: 15),
                    ),
                  );
                });
              }
            }
          },
          itemClick: (prediction) {
            _controller.text = prediction.description ?? '';
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          },
        ),
      ),
    );
  }
}
