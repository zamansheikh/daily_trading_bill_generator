// Entry point used only for UI automation and screenshots:
//   flutter run -t lib/driver_main.dart --dart-define=DTBG_IMPORT=/path/a.pdf;/path/b.pdf
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages -- dev-only entry point, flutter_driver is a dev dependency.
import 'package:flutter_driver/driver_extension.dart';

import 'app/app.dart';
import 'main.dart' as app;

const _importFiles = String.fromEnvironment('DTBG_IMPORT');

Future<void> main() async {
  enableFlutterDriverExtension();
  final state = await app.bootstrap();
  if (_importFiles.isNotEmpty) {
    await state.importFiles(_importFiles.split(';').where((s) => s.isNotEmpty).toList());
  }
  runApp(DailyTradingApp(state: state));
}
