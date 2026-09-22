import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/catalogue_screen.dart';
import 'screens/history_screen.dart';
import 'screens/import_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

class DailyTradingApp extends StatelessWidget {
  const DailyTradingApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: 'Daily Trading Bill Generator',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.light,
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.upload_file_outlined, Icons.upload_file, 'Import'),
    (Icons.history_outlined, Icons.history, 'History'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Catalogue'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final body = IndexedStack(
      index: _index,
      children: const [ImportScreen(), HistoryScreen(), CatalogueScreen(), SettingsScreen()],
    );
    if (!compact) {
      final extended = context.isWide;
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            extended: extended,
            minExtendedWidth: 200,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
              child: extended
                  ? Row(children: [
                      _logo(context),
                      const SizedBox(width: 10),
                      const Text('Daily Trading', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ])
                  : _logo(context),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }

  Widget _logo(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: kBrandGreen, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.receipt_long, color: Colors.white, size: 22),
      );
}
