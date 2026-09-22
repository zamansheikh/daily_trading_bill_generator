import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ordersheet/order_sheet_xlsx.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Arrange the outlets (drag to sort), choose the block size, and build the
/// order sheet. The sequence is remembered for next time.
class OrderSheetScreen extends StatefulWidget {
  const OrderSheetScreen({super.key, required this.orders});
  final List<ImportedOrder> orders;

  @override
  State<OrderSheetScreen> createState() => _OrderSheetScreenState();
}

class _OrderSheetScreenState extends State<OrderSheetScreen> {
  late List<OrderSheetColumn> _columns;
  late final TextEditingController _title;
  late final TextEditingController _perBlock;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _columns = state.orderSheetColumns(widget.orders);
    _title = TextEditingController(text: 'Order sheet ${DateFormat('dd-MMM-yyyy').format(state.supplyDate)}');
    _perBlock = TextEditingController(text: '${state.outletsPerBlock}');
  }

  @override
  void dispose() {
    _title.dispose();
    _perBlock.dispose();
    super.dispose();
  }

  int get _blockSize => (int.tryParse(_perBlock.text) ?? 11).clamp(1, 60);

  Future<void> _generate() async {
    final state = context.read<AppState>();
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);
    try {
      await state.setOutletsPerBlock(_blockSize);
      await state.saveOutletOrder(_columns.map((c) => c.label).toList());
      final path = await state.generateOrderSheet(_columns, title: title);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order sheet saved: ${p.basename(path)} (${_columns.length} POs)'),
        action: SnackBarAction(
          label: isMobile ? 'Share' : 'Open',
          onPressed: () => isMobile ? SharePlus.instance.share(ShareParams(files: [XFile(path)])) : OpenFilex.open(path),
        ),
      ));
    } catch (e) {
      if (mounted) await showMessage(context, 'Could not build the order sheet', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final scheme = Theme.of(context).colorScheme;
    final blockSize = _blockSize;
    final blocks = _columns.isEmpty ? 0 : ((_columns.length - 1) ~/ blockSize) + 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order sheet'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _columns = sortAlphabetically(_columns)),
            icon: const Icon(Icons.sort_by_alpha),
            label: const Text('Sort A-Z'),
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            FilledButton.icon(onPressed: _busy ? null : _generate, icon: const Icon(Icons.grid_on), label: const Text('Generate')),
            const SizedBox(width: 12),
          ],
        ],
      ),
      floatingActionButton: compact
          ? FloatingActionButton.extended(heroTag: 'fab-order-sheet', onPressed: _busy ? null : _generate, icon: const Icon(Icons.grid_on), label: const Text('Generate'))
          : null,
      body: Stack(children: [
        PageBody(
          maxWidth: 900,
          child: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 12 : 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(child: TextField(controller: _title, decoration: const InputDecoration(labelText: 'Sheet name'))),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _perBlock,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Per block'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Drag the handles to put the ${_columns.length} outlets in your sequence. Every $blockSize outlets form one block with its own total column ($blocks block(s)). The order is remembered for next time.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ]),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                buildDefaultDragHandles: false,
                itemCount: _columns.length,
                onReorderItem: (from, to) => setState(() {
                  final c = _columns.removeAt(from);
                  _columns.insert(to, c);
                }),
                itemBuilder: (ctx, i) {
                  final c = _columns[i];
                  final blockStart = i % blockSize == 0;
                  return Column(
                    key: ValueKey(c.po.poNumber),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (blockStart)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                          child: Row(children: [
                            Text('Sheet ${i ~/ blockSize + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                            const SizedBox(width: 8),
                            const Expanded(child: Divider()),
                          ]),
                        ),
                      Card(
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        child: ListTile(
                          dense: true,
                          leading: SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(color: scheme.onSurfaceVariant))),
                          title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${c.po.poNumber}  |  ${c.po.items.length} items  |  Tk ${money.format(c.po.computedTotal)}'),
                          trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ]),
        ),
        if (_busy) const BusyOverlay(message: 'Building order sheet...'),
      ]),
    );
  }
}
