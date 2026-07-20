import '../domain/models/clip_type.dart';
import '../domain/models/timeline_clip.dart';
import '../domain/models/timeline_track.dart';
import '../domain/models/track_type.dart';

/// Resolves what the timeline should render at a specific global position.
class TimelineRenderResolver {
  const TimelineRenderResolver._();

  /// Tracks are expected in visual top-to-bottom order. The first active,
  /// visible video clip wins; lower video tracks are fallback layers.
  static TimelineClip? topVisualClip(
    List<TimelineTrack> tracks,
    Duration position,
  ) {
    for (final track in tracks.where(
      (track) => track.type == TrackType.video && !track.hidden,
    )) {
      for (final clip in track.clips) {
        if (clip.type == ClipType.video &&
            clip.visible &&
            clip.start <= position &&
            position < clip.start + clip.duration) {
          return clip;
        }
      }
    }
    return null;
  }

  /// Unlike video tracks, every active audio clip is returned so they can be
  /// played together as a mix.
  static List<TimelineClip> activeAudioClips(
    List<TimelineTrack> tracks,
    Duration position,
  ) {
    return tracks
        .where(
          (track) =>
              track.type == TrackType.audio &&
              !track.hidden &&
              !track.muted,
        )
        .expand((track) => track.clips)
        .where(
          (clip) =>
              clip.type == ClipType.audio &&
              clip.visible &&
              !clip.muted &&
              clip.start <= position &&
              position < clip.start + clip.duration,
        )
        .toList(growable: false);
  }
}
