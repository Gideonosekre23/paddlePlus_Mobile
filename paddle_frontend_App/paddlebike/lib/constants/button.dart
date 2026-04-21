import 'package:flutter/material.dart';

class ButtonWidget extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const ButtonWidget({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25.0),

      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(250, 50),
          backgroundColor: const Color.fromARGB(255, 2, 2, 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            color: Color.fromARGB(255, 214, 212, 212),
          ),
        ),
      ),
    );
  }
}
