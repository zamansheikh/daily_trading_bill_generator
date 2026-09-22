import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'po_detail_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _dragging = false;

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      dialogTitle: 'Choose purchase order PDFs',
    );
    if (result == null) return;
    await _import(result.files.map((f) => f.path).whereType<String>().toList());
  }

  Future<void> _import(List<String> paths) async {
    final pdfs = paths.where((p) => p.toLowerCase().endsWith('.pdf')).toList();
    if (pdfs.isEmpty) return;
    final state = context.read<AppState>();
    final summary = await state.importFiles(pdfs);
    if (!mounted) return;
    final msg = StringBuffer('Read ${summary.orders} purchase order(s) from ${summary.files} file(s).');
    if (summary.errors.isNotEmpty) {
      msg.write('\n\nNotes:\n');
      msg.writeAll(summary.errors, '\n');
      await showMessage(context, 'Import finished', msg.toString());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
    }
  }

  Future<void> _generate() async {
    final state = context.read<AppState>();
    final targets = state.orders.where((o) => o.selected).toList();
    if (targets.isEmpty) return;
    final unmatched = targets.where((o) => o.hasUnmatched).length;
    final regen = targets.where((o) => o.memoNumber != null).length;
    final ok = await confirm(
      context,
      title: 'Generate ${targets.length} memo(s)?',
      action: 'Generate',
      message: [
        'Supply date: ${shortDate.format(state.supplyDate)}',
        'Memo numbers start at ${state.nextMemoNumber}.',
        if (regen > 0) '$regen order(s) already have a memo number and will be regenerated with the same number.',
        if (unmatched > 0) 'Warning: $unmatched order(s) contain products not in the catalogue. They will be printed as extra lines without a Bangla name.',
      ].join('\n\n'),
    );
    if (!ok) return;
    final result = await state.generateMemos(targets);
    if (!mounted) return;
    final files = [
      for (final o in result.generated) ...[
        if (o.memoPath != null) o.memoPath!,
        if (o.xlsxPath != null) o.xlsxPath!,
      ],
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Memos generated'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text([
            '${result.generated.length} memo(s) saved${isMobile ? '.' : ' to:\n${result.outputDir}'}',
            if (result.errors.isNotEmpty) 'Errors:\n${result.errors.join('\n')}',
          ].join('\n\n')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          if (isMobile && files.isNotEmpty)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                SharePlus.instance.share(ShareParams(files: files.map(XFile.new).toList(), title: 'Daily Trading memos'));
              },
              icon: const Icon(Icons.share),
              label: const Text('Share files'),
            )
          else
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                OpenFilex.open(result.outputDir);
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Open folder'),
            ),
        ],
      ),
    );
  }

  /// Consolidated order sheet (products x outlets) for the selected orders.
  Future<void> _orderSheet() async {
    final state = context.read<AppState>();
    final targets = state.orders.where((o) => o.selected).toList();
    if (targets.isEmpty) return;
    final title = await promptText(
      context,
      title: 'Order sheet name',
      initial: 'Order sheet ${DateFormat('dd-MMM-yyyy').format(state.supplyDate)}',
      hint: 'e.g. Order sheet SEP-2 (DLCL)',
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    final path = await state.generateOrderSheet(targets, title: title.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Order sheet saved: ${p.basename(path)} (${targets.length} POs)'),
      action: SnackBarAction(
        label: isMobile ? 'Share' : 'Open',
        onPressed: () => isMobile ? SharePlus.instance.share(ShareParams(files: [XFile(path)])) : OpenFilex.open(path),
      ),
    ));
  }

  Future<void> _pickSupplyDate() async {
    final state = context.read<AppState>();
    final d = await showDatePicker(context: context, initialDate: state.supplyDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) state.setSupplyDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final orders = state.orders;
    final selected = orders.where((o) => o.selected).length;
    final compact = context.isCompact;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Purchase orders'),
        actions: [
          if (orders.isNotEmpty)
            IconButton(
              tooltip: 'Clear list',
              icon: const Icon(Icons.clear_all),
              onPressed: state.busy
                  ? null
                  : () async {
                      if (await confirm(context, title: 'Clear the list?', message: 'Orders stay in History; only this list is emptied.', action: 'Clear')) {
                        state.clearOrders();
                      }
                    },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(children: [
        PageBody(
          child: Column(children: [
            _toolbar(context, state, selected, compact),
            Expanded(
              child: orders.isEmpty
                  ? _emptyState(context)
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(compact ? 0 : 16, 4, compact ? 0 : 16, 96),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => SizedBox(height: compact ? 0 : 8),
                      itemBuilder: (ctx, i) => _OrderCard(order: orders[i], compact: compact),
                    ),
            ),
          ]),
        ),
        if (_dragging)
          Container(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.file_download, size: 40, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 10),
                    const Text('Drop PDF files here', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
        if (state.busy) BusyOverlay(message: state.busyMessage),
      ]),
      floatingActionButton: orders.isNotEmpty && compact
          ? FloatingActionButton.extended(
              heroTag: 'fab-generate',
              onPressed: selected == 0 || state.busy ? null : _generate,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text('Generate $selected'),
            )
          : null,
    );

    if (!isDesktop) return scaffold;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        _import(d.files.map((f) => f.path).toList());
      },
      child: scaffold,
    );
  }

  Widget _toolbar(BuildContext context, AppState state, int selected, bool compact) {
    final orders = state.orders;
    final verified = orders.where((o) => o.isClean).length;
    final attention = orders.length - verified;
    final total = orders.fold(0.0, (s, o) => s + o.po.computedTotal);

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 12 : 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(onPressed: state.busy ? null : _pickFiles, icon: const Icon(Icons.file_open), label: const Text('Choose PO PDFs')),
          OutlinedButton.icon(onPressed: _pickSupplyDate, icon: const Icon(Icons.event), label: Text('Supply ${shortDate.format(state.supplyDate)}')),
          Chip(
            avatar: const Icon(Icons.tag, size: 16),
            label: Text('Next memo ${state.nextMemoNumber}'),
            visualDensity: VisualDensity.compact,
          ),
        ]),
        if (orders.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            StatCard(label: 'orders', value: '${orders.length}', icon: Icons.receipt_long),
            StatCard(label: 'verified', value: '$verified', icon: Icons.verified, color: kChainGreen),
            if (attention > 0) StatCard(label: 'need attention', value: '$attention', icon: Icons.warning_amber, color: Colors.orange.shade800),
            StatCard(label: 'total Tk', value: money.format(total), icon: Icons.payments_outlined),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(
              value: selected == orders.length ? true : (selected == 0 ? false : null),
              tristate: true,
              onChanged: (v) => state.selectAll(v ?? false),
            ),
            Expanded(child: Text('$selected of ${orders.length} selected', style: Theme.of(context).textTheme.bodyMedium)),
            if (!compact) ...[
              OutlinedButton.icon(
                onPressed: selected == 0 || state.busy ? null : _orderSheet,
                icon: const Icon(Icons.grid_on),
                label: const Text('Order sheet'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: selected == 0 || state.busy ? null : _generate,
                icon: const Icon(Icons.picture_as_pdf),
                label: Text('Generate $selected memo(s)'),
              ),
            ] else
              IconButton(
                tooltip: 'Order sheet for selected',
                icon: const Icon(Icons.grid_on),
                onPressed: selected == 0 || state.busy ? null : _orderSheet,
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _emptyState(BuildContext context) => EmptyHint(
        icon: Icons.upload_file,
        title: 'No purchase orders yet',
        subtitle: isDesktop
            ? 'Drop purchase order PDFs anywhere on this window, or choose them with the button above. Each PO in a file becomes one memo.'
            : 'Choose purchase order PDFs with the button above. Each PO in a file becomes one memo.',
      );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.compact});
  final ImportedOrder order;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final po = order.po;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, status) = order.hasUnmatched
        ? (Icons.error_outline, scheme.error, '${order.unmatchedCount} not in catalogue')
        : order.hasWarnings || !po.totalsMatch
            ? (Icons.warning_amber, Colors.orange.shade800, 'Check totals')
            : (Icons.verified, kChainGreen, 'Verified');

    final title = Row(children: [
      Flexible(child: Text(order.outletDisplayName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      ChainChip(po.chain, dense: compact),
    ]);
    final noteText = po.note.isEmpty ? '' : '  |  Note: ${po.note}';
    final meta = Text('${po.poNumber}  |  ${po.poDate}  |  ${po.items.length} items$noteText', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant));
    final suggestions = state.suggestionsFor(order).where((s) => s.itemIndex != null || s.kind.name == 'outletName').length;
    final pills = Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      StatusPill(icon: icon, label: status, color: color),
      if (suggestions > 0) StatusPill(icon: Icons.auto_fix_high, label: '$suggestions fix(es) suggested', color: Colors.orange.shade800),
      if (po.removedItems.isNotEmpty) StatusPill(icon: Icons.remove_shopping_cart_outlined, label: '${po.removedItems.length} line(s) removed', color: scheme.onSurfaceVariant),
      if (order.memoNumber != null) StatusPill(icon: Icons.tag, label: 'Memo ${order.memoNumber}', color: scheme.primary),
      Text('Tk ${money.format(po.computedTotal)}', style: const TextStyle(fontWeight: FontWeight.w600)),
    ]);

    final menu = PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (v) {
        switch (v) {
          case 'open':
            OpenFilex.open(order.memoPath!);
          case 'share':
            SharePlus.instance.share(ShareParams(files: [XFile(order.memoPath!), if (order.xlsxPath != null) XFile(order.xlsxPath!)]));
          case 'xlsx':
            OpenFilex.open(order.xlsxPath!);
          case 'remove':
            state.removeOrder(order);
        }
      },
      itemBuilder: (_) => [
        if (order.memoPath != null) const PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('Open memo PDF'), dense: true)),
        if (order.xlsxPath != null) const PopupMenuItem(value: 'xlsx', child: ListTile(leading: Icon(Icons.table_chart), title: Text('Open memo Excel'), dense: true)),
        if (order.memoPath != null) const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('Share memo files'), dense: true)),
        const PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.close), title: Text('Remove from list'), dense: true)),
      ],
    );

    final content = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PoDetailScreen(order: order))),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, compact ? 6 : 8, 4, compact ? 6 : 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Checkbox(value: order.selected, onChanged: (v) => state.toggleSelected(order, v ?? false)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              const SizedBox(height: 3),
              meta,
              const SizedBox(height: 6),
              pills,
            ]),
          ),
          menu,
          if (!compact) Icon(Icons.chevron_right, color: scheme.outline),
        ]),
      ),
    );

    if (compact) {
      return Column(children: [content, const Divider()]);
    }
    return Card(child: content);
  }
}
