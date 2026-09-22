import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/app_database.dart';
import '../state/app_state.dart' show AppState;
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final compact = context.isCompact;
    final q = _query.toLowerCase();
    final memos = state.history
        .where((m) => q.isEmpty || m.outletDisplayName.toLowerCase().contains(q) || m.po.poNumber.toLowerCase().contains(q) || '${m.memoNumber}'.contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generated memos'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: state.refreshHistory), const SizedBox(width: 4)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 0, compact ? 12 : 16, 10),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search memo number, outlet or PO', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: PageBody(
        child: memos.isEmpty
            ? EmptyHint(
                icon: Icons.history,
                title: state.history.isEmpty ? 'No memos generated yet' : 'Nothing matches',
                subtitle: state.history.isEmpty ? 'Memos you generate appear here with their number, outlet and file.' : null,
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(compact ? 0 : 16, 8, compact ? 0 : 16, 24),
                itemCount: memos.length,
                separatorBuilder: (_, _) => SizedBox(height: compact ? 0 : 8),
                itemBuilder: (ctx, i) => _MemoTile(memo: memos[i], compact: compact, onReload: () => _reload(state, memos[i])),
              ),
      ),
    );
  }

  void _reload(AppState state, StoredOrder stored) {
    state.loadStoredOrder(stored);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${stored.po.poNumber} added to the Import list for editing.')));
  }
}

class _MemoTile extends StatelessWidget {
  const _MemoTile({required this.memo, required this.compact, required this.onReload});
  final StoredOrder memo;
  final bool compact;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final exists = memo.memoPath != null && File(memo.memoPath!).existsSync();
    final xlsx = memo.memoPath == null ? null : AppState.xlsxPathFor(memo.memoPath!);
    final hasXlsx = xlsx != null && File(xlsx).existsSync();
    final tile = ListTile(
      leading: Container(
        width: 52,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Text('${memo.memoNumber}', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 13)),
      ),
      title: Row(children: [
        Flexible(child: Text(memo.outletDisplayName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        ChainChip(memo.po.chain, dense: true),
      ]),
      subtitle: Text(
        '${memo.po.poNumber}  |  supplied ${memo.supplyDate == null ? '-' : shortDate.format(memo.supplyDate!)}  |  Tk ${money.format(memo.po.computedTotal)}${exists ? '' : '  |  file missing'}',
        style: TextStyle(color: exists ? null : scheme.error),
      ),
      trailing: compact
          ? PopupMenuButton<String>(
              onSelected: (v) => _action(v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'open', enabled: exists, child: const ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('Open PDF'), dense: true)),
                PopupMenuItem(value: 'xlsx', enabled: hasXlsx, child: const ListTile(leading: Icon(Icons.table_chart), title: Text('Open Excel'), dense: true)),
                PopupMenuItem(value: 'share', enabled: exists, child: const ListTile(leading: Icon(Icons.share), title: Text('Share'), dense: true)),
                const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_document), title: Text('Edit / regenerate'), dense: true)),
              ],
            )
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Open PDF', icon: const Icon(Icons.picture_as_pdf), onPressed: exists ? () => _action('open') : null),
              IconButton(tooltip: 'Open Excel', icon: const Icon(Icons.table_chart), onPressed: hasXlsx ? () => _action('xlsx') : null),
              IconButton(tooltip: 'Share', icon: const Icon(Icons.share), onPressed: exists ? () => _action('share') : null),
              IconButton(tooltip: 'Load into Import list to edit or regenerate', icon: const Icon(Icons.edit_document), onPressed: () => _action('edit')),
            ]),
    );
    if (compact) return Column(children: [tile, const Divider()]);
    return Card(child: tile);
  }

  void _action(String v) {
    switch (v) {
      case 'open':
        OpenFilex.open(memo.memoPath!);
      case 'xlsx':
        OpenFilex.open(AppState.xlsxPathFor(memo.memoPath!));
      case 'share':
        final x = AppState.xlsxPathFor(memo.memoPath!);
        SharePlus.instance.share(ShareParams(files: [XFile(memo.memoPath!), if (File(x).existsSync()) XFile(x)]));
      case 'edit':
        onReload();
    }
  }
}
