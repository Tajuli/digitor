import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Digitor app stays UI-only and delegates processing to DigitorEngine', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue);

    final forbidden = <RegExp>[
      RegExp(r'package:ffmpeg', caseSensitive: false),
      RegExp(r'ffmpeg_kit', caseSensitive: false),
      RegExp(r'androidx\.media3', caseSensitive: false),
      RegExp(r'package:video_compress', caseSensitive: false),
      RegExp(r'DigitorProductionMediaSource\.open\('),
    ];

    final violations = <String>[];
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final pattern in forbidden) {
        if (pattern.hasMatch(source)) {
          violations.add('${entity.path}: ${pattern.pattern}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Digitor must not own media/render processing. Route it through '
          'DigitorEngine instead.\n${violations.join('\n')}',
    );
  });

  test('DigitorEngine gateway is the app processing boundary', () {
    final gateway = File('lib/engine/digitor_engine_gateway.dart');
    expect(gateway.existsSync(), isTrue);

    final source = gateway.readAsStringSync();
    expect(source, contains('package:digitor_engine_ffi/digitor_engine_ffi.dart'));
    expect(source, contains('DigitorNodeGraph'));
    expect(source, contains('DigitorProductionMediaPipeline'));
    expect(source, contains('DigitorFlutterPlatformHost'));
    expect(source, isNot(contains('DigitorProductionMediaSource.open(')));
  });
}
