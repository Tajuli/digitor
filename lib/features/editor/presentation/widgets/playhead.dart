import 'package:flutter/material.dart';

class Playhead extends StatelessWidget {
  const Playhead({
    super.key,
    this.color = Colors.redAccent,
    this.height = 72,
    this.width = 2,
    this.showHandle = true,
  });

  final Color color;
  final double height;
  final double width;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 24,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            if (showHandle)
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(.35),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),

            Positioned(
              top: showHandle ? 14 : 0,
              bottom: 0,
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
