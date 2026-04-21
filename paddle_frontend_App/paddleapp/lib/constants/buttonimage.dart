import 'package:flutter/material.dart';

class ButtonImage extends StatelessWidget {
  final String imagePath;
  final VoidCallback onPressed;
  final double width;
  final double height;

  const ButtonImage({
    super.key,
    required this.imagePath,
    required this.onPressed,
    this.width = 40,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(10),
          minimumSize: Size(width + 20, height + 20),
        ),
        child: Image.asset(
          imagePath,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) {
            print('Error loading image: $error');
            return Icon(Icons.error, size: width);
          },
        ),
      ),
    );
  }
}
