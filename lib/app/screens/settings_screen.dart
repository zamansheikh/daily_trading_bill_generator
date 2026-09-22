import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final compact = context.isCompact;
    Widget section(String title, List<Widget> children) => Padding(
          padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 12 : 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary))),
            Card(child: Column(children: children)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageBody(
        maxWidth: 820,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          section('Memos', [
            ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('Next memo number'),
              subtitle: Text('${state.nextMemoNumber}. Numbers are assigned in order as memos are generated.'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final v = await promptText(context, title: 'Next memo number', initial: '${state.nextMemoNumber}', keyboard: TextInputType.number);
                final n = int.tryParse(v ?? '');
                if (n != null && n > 0) await state.setNextMemoNumber(n);
              },
            ),
            if (!isMobile) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Output folder'),
                subtitle: Text('${state.outputDir}\nA sub-folder per supply date is created inside it.'),
                isThreeLine: true,
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose where memos are saved');
                  if (dir != null) await state.setOutputDir(dir);
                },
              ),
            ],
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.table_chart_outlined),
              title: const Text('Also export Excel (.xlsx)'),
              subtitle: const Text('Writes an editable Excel copy of every memo next to the PDF, with the same layout and live totals.'),
              value: state.exportXlsx,
              onChanged: state.setExportXlsx,
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.trending_up),
              title: const Text('Learn prices from purchase orders'),
              subtitle: const Text('When a memo is generated, the rate on the PO becomes the chain\'s list price for that product.'),
              value: state.learnPrices,
              onChanged: state.setLearnPrices,
            ),
          ]),
          section('How it works', const [
            ListTile(leading: Icon(Icons.looks_one_outlined), title: Text('Import PO PDFs'), subtitle: Text('Daily Shopping or Best Buy orders. One file may hold many POs and a PO may span pages.')),
            ListTile(leading: Icon(Icons.looks_two_outlined), title: Text('Every line is checked'), subtitle: Text('quantity x rate = total, and all lines must add up to the PO grand total.')),
            ListTile(leading: Icon(Icons.looks_3_outlined), title: Text('Lines are matched to the catalogue'), subtitle: Text('By code, or by name and size when the buyer uses its own codes. Unmatched lines are highlighted.')),
            ListTile(leading: Icon(Icons.looks_4_outlined), title: Text('Generate memos'), subtitle: Text('One Letter-size PDF per PO, named "<memo no>(<outlet>).pdf".')),
          ]),
          section('Built-in catalogue', [
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Shipped catalogue'),
              subtitle: Text('${state.catalog.products.length} products with Bangla names, Daily Shopping and Best Buy price lists and Best Buy codes are built in. Add or edit products in the Catalogue tab.'),
              isThreeLine: true,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore shipped catalogue'),
              subtitle: const Text('Replaces all products, prices and codes with the built-in defaults. Orders and memos are kept.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final ok = await confirm(
                  context,
                  title: 'Restore shipped catalogue?',
                  message: 'Every product, price and Best Buy code you changed or added will be replaced by the built-in defaults. This cannot be undone.',
                  action: 'Restore',
                  destructive: true,
                );
                if (!ok) return;
                await state.resetCatalog();
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Catalogue restored to the shipped defaults.')));
              },
            ),
          ]),
          section('About', [
            const ListTile(leading: Icon(Icons.info_outline), title: Text('Daily Trading Bill Generator'), subtitle: Text('Version 1.2.0')),
            const Divider(),
            const _DeveloperCredit(),
          ]),
        ]),
      ),
    );
  }
}

class _DeveloperCredit extends StatelessWidget {
  const _DeveloperCredit();

  static final _github = Uri.parse('https://github.com/zamansheikh');
  static final _facebook = Uri.parse('https://fb.com/zamansheikh.404');

  Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            child: Text('ZS', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Built with '),
                  TextSpan(text: '\u2764', style: TextStyle(color: Colors.red.shade600)),
                  const TextSpan(text: ' by '),
                  const TextSpan(text: 'Zaman Sheikh', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              Text('Software engineer, Dhaka', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _open(context, _github), icon: const Icon(Icons.code), label: const Text('github.com/zamansheikh')),
          OutlinedButton.icon(onPressed: () => _open(context, _facebook), icon: const Icon(Icons.facebook), label: const Text('fb.com/zamansheikh.404')),
        ]),
      ]),
    );
  }
}
