import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/chain.dart';
import '../../domain/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final compact = context.isCompact;
    final q = _filter.toLowerCase();
    final products = state.catalog.products.where((p) => q.isEmpty || p.nameEn.toLowerCase().contains(q) || p.dtCode.contains(q) || p.nameBn.contains(q) || p.size.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product catalogue'),
        actions: [
          if (!compact) ...[
            FilledButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('Add product')),
            const SizedBox(width: 12),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 0, compact ? 12 : 16, 10),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search name, Bangla name, code or size', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
      ),
      floatingActionButton: compact ? FloatingActionButton(heroTag: 'fab-add-product', onPressed: () => _edit(context, null), tooltip: 'Add product', child: const Icon(Icons.add)) : null,
      body: PageBody(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 8, compact ? 12 : 16, 8),
            child: Text(
              'Printed on memos in this order. DS = Daily Shopping memos, BB = Best Buy memos. A blank price prints as an empty cell; '
              'an unticked chain hides the product from that chain\'s memo. Prices update from each new PO when "Learn prices" is on.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: compact ? _list(context, state, products) : _table(context, state, products)),
        ]),
      ),
    );
  }

  Widget _list(BuildContext context, AppState state, List<Product> products) {
    final scheme = Theme.of(context).colorScheme;
    String price(Chain c, Product p) {
      final v = state.catalog.price(c, p.id);
      return v == null ? '-' : money.format(v);
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: products.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (ctx, i) {
        final p = products[i];
        final ds = state.catalog.isIncluded(Chain.dailyShopping, p.id);
        final bb = state.catalog.isIncluded(Chain.bestBuy, p.id);
        return ListTile(
          onTap: () => _edit(context, p),
          leading: SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(color: scheme.onSurfaceVariant))),
          title: Row(children: [
            Expanded(child: Text('${p.nameEn} ${p.size}', style: TextStyle(fontWeight: FontWeight.w600, color: p.active ? null : scheme.outline))),
            Text(p.nameBn, style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
          subtitle: Text('${p.dtCode}   DS ${price(Chain.dailyShopping, p)}${ds ? '' : ' (off)'}   BB ${price(Chain.bestBuy, p)}${bb ? '' : ' (off)'}'),
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
  }

  Widget _table(BuildContext context, AppState state, List<Product> products) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (ctx, c) => SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  columnSpacing: 14,
                  dataRowMinHeight: 38,
                  dataRowMaxHeight: 38,
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('DT code')),
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Bangla')),
                    DataColumn(label: Text('Size')),
                    DataColumn(label: Text('DS price'), numeric: true),
                    DataColumn(label: Text('DS')),
                    DataColumn(label: Text('BB price'), numeric: true),
                    DataColumn(label: Text('BB')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [for (var i = 0; i < products.length; i++) _row(context, state, i + 1, products[i])],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, AppState state, int n, Product p) {
    final ds = state.catalog.chainProduct(Chain.dailyShopping, p.id);
    final bb = state.catalog.chainProduct(Chain.bestBuy, p.id);
    final scheme = Theme.of(context).colorScheme;
    String price(ChainProduct? cp) => cp?.price == null ? '' : money.format(cp!.price);
    Widget tick(bool on) => Icon(on ? Icons.check_circle : Icons.remove_circle_outline, size: 18, color: on ? kChainGreen : scheme.outline);
    return DataRow(
      color: p.active ? null : WidgetStatePropertyAll(scheme.surfaceContainerHighest.withValues(alpha: 0.5)),
      onSelectChanged: (_) => _edit(context, p),
      cells: [
        DataCell(Text('$n', style: TextStyle(color: scheme.onSurfaceVariant))),
        DataCell(Text(p.dtCode)),
        DataCell(Text(p.nameEn, style: const TextStyle(fontWeight: FontWeight.w500))),
        DataCell(Text(p.nameBn)),
        DataCell(Text(p.size)),
        DataCell(Text(price(ds))),
        DataCell(tick(ds?.included ?? true)),
        DataCell(Text(price(bb))),
        DataCell(tick(bb?.included ?? false)),
        DataCell(IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _edit(context, p))),
      ],
    );
  }

  Future<void> _edit(BuildContext context, Product? existing) async {
    final state = context.read<AppState>();
    await showDialog<void>(context: context, builder: (_) => _ProductDialog(state: state, product: existing));
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.state, this.product});
  final AppState state;
  final Product? product;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _code;
  late final TextEditingController _nameEn;
  late final TextEditingController _nameBn;
  late final TextEditingController _size;
  late final TextEditingController _order;
  late final TextEditingController _dsPrice;
  late final TextEditingController _bbPrice;
  late final TextEditingController _bbAlias;
  late bool _dsIncluded;
  late bool _bbIncluded;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final cat = widget.state.catalog;
    final ds = p == null ? null : cat.chainProduct(Chain.dailyShopping, p.id);
    final bb = p == null ? null : cat.chainProduct(Chain.bestBuy, p.id);
    _code = TextEditingController(text: p?.dtCode ?? '');
    _nameEn = TextEditingController(text: p?.nameEn ?? '');
    _nameBn = TextEditingController(text: p?.nameBn ?? '');
    _size = TextEditingController(text: p?.size ?? '');
    _order = TextEditingController(text: '${p?.sortOrder ?? ((cat.products.isEmpty ? 0 : cat.products.last.sortOrder) + 10)}');
    _dsPrice = TextEditingController(text: ds?.price?.toStringAsFixed(2) ?? '');
    _bbPrice = TextEditingController(text: bb?.price?.toStringAsFixed(2) ?? '');
    _bbAlias = TextEditingController();
    _dsIncluded = ds?.included ?? true;
    _bbIncluded = bb?.included ?? true;
    _active = p?.active ?? true;
  }

  @override
  void dispose() {
    for (final c in [_code, _nameEn, _nameBn, _size, _order, _dsPrice, _bbPrice, _bbAlias]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_code.text.trim().isEmpty || _nameEn.text.trim().isEmpty) return;
    final p = Product(
      id: widget.product?.id ?? 0,
      dtCode: _code.text,
      nameEn: _nameEn.text,
      nameBn: _nameBn.text,
      size: _size.text,
      sortOrder: int.tryParse(_order.text) ?? 0,
      active: _active,
    );
    double? parse(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());
    await widget.state.saveProduct(p, chains: {
      Chain.dailyShopping: ChainProduct(chain: Chain.dailyShopping, productId: p.id, included: _dsIncluded, price: parse(_dsPrice.text)),
      Chain.bestBuy: ChainProduct(chain: Chain.bestBuy, productId: p.id, included: _bbIncluded, price: parse(_bbPrice.text)),
    });
    if (_bbAlias.text.trim().isNotEmpty) {
      final saved = widget.state.catalog.byDtCode(p.dtCode.trim());
      if (saved != null) await widget.state.saveAlias(Chain.bestBuy, _bbAlias.text.trim(), saved.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {TextInputType? type}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label)),
        );
    const num = TextInputType.numberWithOptions(decimal: true);
    final narrow = context.isCompact;
    return AlertDialog(
      title: Text(widget.product == null ? 'Add product' : 'Edit product'),
      insetPadding: EdgeInsets.all(narrow ? 12 : 40),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            field(_code, 'Daily Trading code (10 digits)'),
            field(_nameEn, 'Name (English)'),
            field(_nameBn, 'Name (Bangla)'),
            Row(children: [
              Expanded(child: field(_size, 'Size (e.g. 100gm)')),
              const SizedBox(width: 10),
              Expanded(child: field(_order, 'Print order', type: TextInputType.number)),
            ]),
            Row(children: [
              Expanded(child: field(_dsPrice, 'Daily Shopping price', type: num)),
              const SizedBox(width: 10),
              Expanded(child: field(_bbPrice, 'Best Buy price', type: num)),
            ]),
            CheckboxListTile(value: _dsIncluded, onChanged: (v) => setState(() => _dsIncluded = v ?? true), title: const Text('Print on Daily Shopping memos'), dense: true, contentPadding: EdgeInsets.zero),
            CheckboxListTile(value: _bbIncluded, onChanged: (v) => setState(() => _bbIncluded = v ?? true), title: const Text('Print on Best Buy memos'), dense: true, contentPadding: EdgeInsets.zero),
            CheckboxListTile(value: _active, onChanged: (v) => setState(() => _active = v ?? true), title: const Text('Active'), dense: true, contentPadding: EdgeInsets.zero),
            const SizedBox(height: 6),
            field(_bbAlias, 'Add a Best Buy code for this product (optional)'),
          ]),
        ),
      ),
      actions: [
        if (widget.product != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              final ok = await confirm(context, title: 'Delete product?', message: '${widget.product!.nameEn} ${widget.product!.size} will be removed from the catalogue.', action: 'Delete', destructive: true);
              if (ok) {
                await widget.state.deleteProduct(widget.product!.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
