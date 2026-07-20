import 'package:flutter/material.dart';

class Playhead extends StatelessWidget {
  const Playhead({
    super.key,
    required this.x,
    required this.height,
    required this.position,
  });

  final double x;
  final double height;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x,
      top: 0,
      child: Column(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), child: Text(_label(position), style: const TextStyle(color: Colors.white, fontSize: 10))), Container(width: 10, height: 8, color: Colors.red), Container(width: 2, height: height - 30, color: Colors.red)]),
    );
  }
  String _label(Duration value) => '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
