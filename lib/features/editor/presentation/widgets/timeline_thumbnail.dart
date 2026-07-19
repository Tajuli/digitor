import 'dart:io';

import 'package:flutter/material.dart';

class TimelineThumbnail extends StatelessWidget {
  const TimelineThumbnail({
    super.key,
    this.imageFile,
    this.width = 56,
    this.height = 64,
  });

  final File? imageFile;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width,
        height: height,
        color: Colors.grey.shade900,
        child: imageFile == null
            ? _buildPlaceholder()
            : Image.file(
                imageFile!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade700,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.movie_creation_outlined,
          color: Colors.white54,
          size: 20,
        ),
      ),
    );
  }
}
