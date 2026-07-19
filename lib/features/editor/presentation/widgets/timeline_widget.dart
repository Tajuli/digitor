import 'package:digitor/features/editor/application/thumbnail_generator.dart';
import 'package:digitor/features/editor/presentation/widgets/playhead.dart';
import 'package:digitor/features/editor/presentation/widgets/timeline_thumbnail.dart';
import 'package:flutter/material.dart';

class TimelineWidget extends StatelessWidget {
  const TimelineWidget({
    super.key,
    required this.duration,
    this.frames = const [],
  });

  final Duration duration;

  final List<ThumbnailFrame> frames;

  static const double _height = 120;
  static const double _trackHeight = 70;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _height,
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
                    Container(
                      height: _trackHeight,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),

                    ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      itemCount: frames.isEmpty ? 20 : frames.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 2),
                      itemBuilder: (_, index) {
                        if (frames.isEmpty) {
                          return const TimelineThumbnail();
                        }

                        return TimelineThumbnail(
                          imageFile: frames[index].file,
                        );
                      },
                    ),

                    const Playhead(),
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
        const Icon(Icons.timeline, size: 18),

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
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;

    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }
}
