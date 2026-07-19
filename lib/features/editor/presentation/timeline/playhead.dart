import 'package:flutter/material.dart';

class Playhead extends StatelessWidget {
  const Playhead({
    super.key,
    required this.x,
    required this.height,
  });

  final double x;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x,
      top: 0,
      child: Container(
        width: 2,
        height: height,
        color: Colors.red,
      ),
    );
  }
}
