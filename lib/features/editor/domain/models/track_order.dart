import 'timeline_track.dart';
import 'track_type.dart';

/// Keeps the model order consistent with the visual stacking order.
List<TimelineTrack> normalizeTrackOrder(List<TimelineTrack> tracks) => [
      ...tracks.where((track) => track.type == TrackType.video),
      ...tracks.where((track) => track.type == TrackType.audio),
    ];
