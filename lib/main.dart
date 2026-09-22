import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/state/app_state.dart';
import 'data/app_database.dart';

/// Opens the database, loads the banner and prepares the app state.
Future<AppState> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final banner = (await rootBundle.load('assets/images/memo_banner.png')).buffer.asUint8List();
  final db = await AppDatabase.open();
  final state = AppState(db: db, bannerBytes: banner);
  await state.init();
  return state;
}

Future<void> main() async {
  runApp(DailyTradingApp(state: await bootstrap()));
}
