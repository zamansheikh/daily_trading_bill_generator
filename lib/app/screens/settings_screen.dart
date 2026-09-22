import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          section('About', const [
            ListTile(leading: Icon(Icons.info_outline), title: Text('Daily Trading Bill Generator'), subtitle: Text('Version 1.0.0')),
          ]),
        ]),
      ),
    );
  }
}
