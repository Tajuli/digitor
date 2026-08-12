import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/digitor_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bootstrap = await DigitorFlutterProductionBootstrap.resolve();
  if (kDebugMode) {
    debugPrint(
      '[DigitorEngine] bootstrap platform=${bootstrap.platform} '
      'textureHostReady=${bootstrap.textureHostReady} '
      'productionHostRegistered=${bootstrap.productionHostRegistered} '
      'ready=${bootstrap.ready} '
      'diagnostic=${bootstrap.diagnostic}',
    );
  }

  runApp(const DigitorApp());
}
