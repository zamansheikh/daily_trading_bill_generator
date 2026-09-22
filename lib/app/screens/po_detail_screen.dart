import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/catalog/product_matcher.dart';
import '../../domain/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/suggestions_dialog.dart';

class PoDetailScreen extends StatelessWidget {
  const PoDetailScreen({super.key, required this.order});
  final ImportedOrder order;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final po = order.po;
    final compact = context.isCompact;
    final suggestionCount = state.suggestionsFor(order).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(compact ? order.outletDisplayName : '${order.outletDisplayName}  -  ${po.poNumber}', overflow: TextOverflow.ellipsis),
        actions: [
          if (!compact) ...[
            TextButton.icon(
              onPressed: () => _fillMissing(context),
              icon: Icon(Icons.auto_fix_high, color: suggestionCount > 0 ? Colors.orange.shade800 : null),
              label: Text(suggestionCount > 0 ? 'Fill missing ($suggestionCount)' : 'Fill missing'),
            ),
            TextButton.icon(onPressed: () => _preview(context), icon: const Icon(Icons.preview), label: const Text('Preview')),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: state.busy ? null : () => _generateOne(context),
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(order.memoNumber == null ? 'Generate memo' : 'Regenerate ${order.memoNumber}'),
            ),
            const SizedBox(width: 12),
          ] else ...[
            IconButton(
              tooltip: 'Fill missing values',
              icon: Badge.count(count: suggestionCount, isLabelVisible: suggestionCount > 0, child: const Icon(Icons.auto_fix_high)),
              onPressed: () => _fillMissing(context),
            ),
            IconButton(tooltip: 'Preview memo', icon: const Icon(Icons.preview), onPressed: () => _preview(context)),
          ],
        ],
      ),
      floatingActionButton: compact
          ? FloatingActionButton.extended(
              heroTag: 'fab-generate-one',
              onPressed: state.busy ? null : () => _generateOne(context),
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(order.memoNumber == null ? 'Generate memo' : 'Regenerate ${order.memoNumber}'),
            )
          : null,
      body: Stack(children: [
        PageBody(
          child: ListView(padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 12 : 16, 96), children: [
            _header(context, state),
            const SizedBox(height: 12),
            if (po.warnings.isNotEmpty || !po.totalsMatch) ...[_warnings(context), const SizedBox(height: 12)],
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Row(children: [
                Text('Items', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('Tk ${money.format(po.computedTotal)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            if (order.hasUnmatched)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Red lines are not in the catalogue. Pick the right product for each; the buyer\'s code is remembered for next time.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              ),
            if (compact) ..._itemCards(context, state) else _itemsTable(context, state),
          ]),
        ),
        if (state.busy) BusyOverlay(message: state.busyMessage),
      ]),
    );
  }

  Future<void> _fillMissing(BuildContext context) async {
    final state = context.read<AppState>();
    final chosen = await showSuggestionsDialog(context, title: 'Fill missing values', suggestions: state.suggestionsFor(order));
    if (chosen == null || chosen.isEmpty || !context.mounted) return;
    final n = await state.applySuggestions(chosen, order: order);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied $n value(s).')));
  }

  void _preview(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemoPreviewScreen(order: order)));

  Widget _header(BuildContext context, AppState state) {
    final po = order.po;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InfoRow(
            label: 'Name on memo',
            child: Row(children: [
              Expanded(child: Text(order.outletDisplayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              IconButton(
                tooltip: 'Edit the name printed on the memo',
                icon: const Icon(Icons.edit, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final v = await promptText(context, title: 'Name/address printed on memo', initial: order.outletDisplayName);
                  if (v != null && v.trim().isNotEmpty) await state.setOutletDisplayName(order, v);
                },
              ),
            ]),
          ),
          InfoRow(label: 'Chain', child: Align(alignment: Alignment.centerLeft, child: ChainChip(po.chain))),
          InfoRow(label: 'PO number', child: SelectableText(po.poNumber)),
          InfoRow(label: 'PO date', child: Text(po.poDate)),
          InfoRow(label: 'Purchaser', child: Text(po.purchaser)),
          InfoRow(label: 'Outlet on PO', child: Text(po.outletName)),
          InfoRow(label: 'Address', child: Text(po.address)),
          if (po.note.isNotEmpty) InfoRow(label: 'PO note', child: Text(po.note)),
          InfoRow(label: 'Source', child: Text('${po.sourceFile}  (page ${po.pages.join(', ')})')),
          if (order.memoPath != null)
            InfoRow(
              label: 'Memo',
              child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                StatusPill(icon: Icons.tag, label: 'Memo ${order.memoNumber}', color: Theme.of(context).colorScheme.primary),
                TextButton.icon(onPressed: () => OpenFilex.open(order.memoPath!), icon: const Icon(Icons.picture_as_pdf, size: 18), label: const Text('Open PDF')),
                TextButton.icon(
                  onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(order.memoPath!)])),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _warnings(BuildContext context) {
    final po = order.po;
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.warning_amber, color: Colors.orange.shade800), const SizedBox(width: 8), const Text('Check this order', style: TextStyle(fontWeight: FontWeight.w600))]),
          const SizedBox(height: 6),
          for (final w in po.warnings) Text('- $w'),
          if (!po.totalsMatch && po.declaredTotal != null) Text('- Lines sum to ${money.format(po.computedTotal)}, PO total is ${money.format(po.declaredTotal)}.'),
        ]),
      ),
    );
  }

  // Wide layout: a data table.
  Widget _itemsTable(BuildContext context, AppState state) {
    final po = order.po;
    final products = state.catalog.products.where((p) => p.active).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (ctx, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Sl')),
                DataColumn(label: Text('PO code')),
                DataColumn(label: Text('PO name')),
                DataColumn(label: Text('Catalogue product')),
                DataColumn(label: Text('Qty'), numeric: true),
                DataColumn(label: Text('Rate'), numeric: true),
                DataColumn(label: Text('Total'), numeric: true),
              ],
              rows: [for (var i = 0; i < po.items.length; i++) _itemRow(ctx, state, i, po.items[i], products)],
            ),
          ),
        ),
      ),
    );
  }

  DataRow _itemRow(BuildContext context, AppState state, int i, PoItem it, List<Product> products) {
    final kind = order.matchKinds[i];
    final color = switch (kind) {
      MatchKind.none => Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
      MatchKind.name => Colors.amber.withValues(alpha: 0.12),
      MatchKind.code => null,
    };
    return DataRow(
      color: color == null ? null : WidgetStatePropertyAll(color),
      cells: [
        DataCell(Text('${it.sl}')),
        DataCell(Text(it.code)),
        DataCell(Text(it.cleanName)),
        DataCell(SizedBox(width: 260, child: _productDropdown(state, i, it, products))),
        DataCell(Text(_qty(it.quantity)), onTap: () => _editQty(context, state, i, it)),
        DataCell(Text(money.format(it.rate)), onTap: () => _editRate(context, state, i, it)),
        DataCell(Text(money.format(it.total))),
      ],
    );
  }

  // Compact layout: one card per line.
  List<Widget> _itemCards(BuildContext context, AppState state) {
    final po = order.po;
    final products = state.catalog.products.where((p) => p.active).toList();
    final scheme = Theme.of(context).colorScheme;
    return [
      for (var i = 0; i < po.items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            color: switch (order.matchKinds[i]) {
              MatchKind.none => scheme.error.withValues(alpha: 0.06),
              MatchKind.name => Colors.amber.withValues(alpha: 0.10),
              MatchKind.code => null,
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${po.items[i].sl}.', style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(po.items[i].cleanName, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(po.items[i].code, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: 6),
                _productDropdown(state, i, po.items[i], products),
                const SizedBox(height: 6),
                Row(children: [
                  _miniStat(context, 'Qty', _qty(po.items[i].quantity), () => _editQty(context, state, i, po.items[i])),
                  _miniStat(context, 'Rate', money.format(po.items[i].rate), () => _editRate(context, state, i, po.items[i])),
                  _miniStat(context, 'Total', money.format(po.items[i].total), null),
                ]),
              ]),
            ),
          ),
        ),
    ];
  }

  Widget _miniStat(BuildContext context, String label, String value, VoidCallback? onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              Row(children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.edit, size: 12, color: Theme.of(context).colorScheme.outline)],
              ]),
            ]),
          ),
        ),
      );

  Widget _productDropdown(AppState state, int i, PoItem it, List<Product> products) {
    final matched = state.catalog.byId(it.productId);
    return DropdownButtonFormField<int?>(
      isExpanded: true,
      initialValue: matched?.id,
      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      hint: const Text('Not matched: choose a product', style: TextStyle(color: Colors.red)),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('(none)')),
        for (final p in products) DropdownMenuItem<int?>(value: p.id, child: Text('${p.nameEn} ${p.size}  [${p.dtCode}]', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => state.setItemProduct(order, i, v == null ? null : state.catalog.byId(v)),
    );
  }

  Future<void> _editQty(BuildContext context, AppState state, int i, PoItem it) async {
    final v = await promptText(context, title: 'Quantity', initial: _qty(it.quantity), keyboard: const TextInputType.numberWithOptions(decimal: true));
    final q = double.tryParse(v ?? '');
    if (q != null) await state.setItemQuantity(order, i, q);
  }

  Future<void> _editRate(BuildContext context, AppState state, int i, PoItem it) async {
    final v = await promptText(context, title: 'Unit rate', initial: it.rate.toStringAsFixed(2), keyboard: const TextInputType.numberWithOptions(decimal: true));
    final r = double.tryParse(v ?? '');
    if (r != null) await state.setItemRate(order, i, r);
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  Future<void> _generateOne(BuildContext context) async {
    final state = context.read<AppState>();
    final r = await state.generateMemos([order]);
    if (!context.mounted) return;
    if (r.errors.isNotEmpty) {
      await showMessage(context, 'Could not generate', r.errors.join('\n'));
      return;
    }
    final path = order.memoPath!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Saved memo ${order.memoNumber}'),
      action: SnackBarAction(
        label: isMobile ? 'Share' : 'Open',
        onPressed: () => isMobile ? SharePlus.instance.share(ShareParams(files: [XFile(path)])) : OpenFilex.open(path),
      ),
    ));
  }
}

/// On-screen preview of the memo (uses the app's PDF renderer, so what you
/// see is what gets saved).
class MemoPreviewScreen extends StatelessWidget {
  const MemoPreviewScreen({super.key, required this.order});
  final ImportedOrder order;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final doc = state.buildMemo(order);
    return Scaffold(
      appBar: AppBar(title: Text('Memo ${doc.memoNumber} preview', overflow: TextOverflow.ellipsis)),
      body: PdfPreview(
        build: (_) => state.renderMemo(doc),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: AppState.memoFileName(doc.memoNumber, order.outletDisplayName),
      ),
    );
  }
}
