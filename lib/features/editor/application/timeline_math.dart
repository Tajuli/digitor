class TimelineMath {
  const TimelineMath._();

  static double durationToPixels(Duration duration, double pixelsPerSecond) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond * pixelsPerSecond;

  static Duration pixelsToDuration(double pixels, double pixelsPerSecond) {
    if (pixelsPerSecond <= 0) return Duration.zero;
    return Duration(microseconds: (pixels / pixelsPerSecond * Duration.microsecondsPerSecond).round());
  }

  static Duration clampTimelinePosition(Duration position, Duration duration) {
    if (duration <= Duration.zero) return Duration.zero;
    if (position < Duration.zero) return Duration.zero;
    return position > duration ? duration : position;
  }
}
