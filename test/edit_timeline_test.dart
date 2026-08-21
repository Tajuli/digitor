import 'package:flutter_test/flutter_test.dart';
import 'package:digitor/core/engine/edit_timeline.dart';

void main() {
  LinearEditTimeline timeline() => LinearEditTimeline();

  EditTimelineClip append(LinearEditTimeline value, String name, int durationUs) =>
      value.append(
        sourcePath: '/tmp/$name.mp4',
        displayName: '$name.mp4',
        sourceDurationUs: durationUs,
        frameDurationUs: 33333,
        firstFrameNumber: 0,
        width: 1920,
        height: 1080,
      );

  test('multiple clips append contiguously', () {
    final value = timeline();
    final first = append(value, 'one', 5 * 1000000);
    final second = append(value, 'two', 3 * 1000000);

    expect(first.timelineStartUs, 0);
    expect(second.timelineStartUs, 5 * 1000000);
    expect(value.durationUs, 8 * 1000000);
    expect(value.clipAt(6 * 1000000)?.id, second.id);
  });

  test('split preserves source ranges and total duration', () {
    final value = timeline();
    final clip = append(value, 'one', 10 * 1000000);

    final result = value.split(clip.id, 4 * 1000000);

    expect(result.left.sourceInUs, 0);
    expect(result.left.sourceOutUs, 4 * 1000000);
    expect(result.right.sourceInUs, 4 * 1000000);
    expect(result.right.sourceOutUs, 10 * 1000000);
    expect(result.right.timelineStartUs, 4 * 1000000);
    expect(value.durationUs, 10 * 1000000);
  });

  test('delete ripple closes the removed clip gap', () {
    final value = timeline();
    append(value, 'one', 2 * 1000000);
    final second = append(value, 'two', 3 * 1000000);
    final third = append(value, 'three', 4 * 1000000);

    value.delete(second.id);

    expect(value.length, 2);
    expect(value.byId(third.id)?.timelineStartUs, 2 * 1000000);
    expect(value.durationUs, 6 * 1000000);
  });

  test('split is rejected at clip edges', () {
    final value = timeline();
    final clip = append(value, 'one', 5 * 1000000);

    expect(value.canSplit(clip.id, 0), isFalse);
    expect(value.canSplit(clip.id, 5 * 1000000), isFalse);
    expect(value.canSplit(clip.id, 2 * 1000000), isTrue);
  });
}
