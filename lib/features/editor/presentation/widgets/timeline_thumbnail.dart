import 'dart:io';

import 'package:flutter/material.dart';

class TimelineThumbnail extends StatelessWidget {
  const TimelineThumbnail({
    super.key,
    this.imageFile,
    this.width = 60,
    this.height = 64,
    this.selected = false,
  });

  final File? imageFile;
  final double width;
  final double height;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageFile != null
          ? Image.file(
              imageFile!,
              fit: BoxFit.cover,
            )
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xff3A3F47),
                    Color(0xff565C66),
                  ],
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.movie,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
    );
  }
}
