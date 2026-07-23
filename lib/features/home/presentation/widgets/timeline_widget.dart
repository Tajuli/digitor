import 'package:flutter/material.dart';

class TimelineWidget extends StatelessWidget {
  const TimelineWidget({
    super.key,
    this.duration = const Duration(minutes: 1),
  });

  final Duration duration;

  static const double _timelineHeight = 120;
  static const double _trackHeight = 68;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _timelineHeight,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TimelineHeader(duration: duration),
              const SizedBox(height: 10),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const _TrackBackground(),
                    Positioned.fill(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: 20,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 2),
                        itemBuilder: (_, index) {
                          return const _ThumbnailPlaceholder();
                        },
                      ),
                    ),
                    const _PlayHead(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.duration,
  });

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        const Icon(
          Icons.timeline,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          "Timeline",
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          _format(duration),
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return "${minutes.toString().padLeft(2, '0')}:"
        "${seconds.toString().padLeft(2, '0')}";
  }
}

class _TrackBackground extends StatelessWidget {
  const _TrackBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: TimelineWidget._trackHeight,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [
            Color(0xff3B3F46),
            Color(0xff5A606B),
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.movie_creation_outlined,
          color: Colors.white70,
          size: 18,
        ),
      ),
    );
  }
}

class _PlayHead extends StatelessWidget {
  const _PlayHead();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
