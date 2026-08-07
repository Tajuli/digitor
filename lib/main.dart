import 'package:digitor/app/digitor_app.dart';
import 'package:digitor/core/engine/digitor_engine_runtime.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DigitorEngineRuntime.instance.initialize();
  runApp(const DigitorApp());
}
