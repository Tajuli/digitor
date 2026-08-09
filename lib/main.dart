import 'package:digitor/app/digitor_app.dart';
import 'package:digitor/core/engine/digitor_engine_gateway.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DigitorEngineGateway.instance.initialize();
  runApp(const DigitorApp());
}
