import 'package:flutter/material.dart';

import '../../core/suggest/suggestions.dart';

/// Lets the user review proposed values and pick which to apply.
/// Returns the selected suggestions, or null when cancelled.
Future<List<Suggestion>?> showSuggestionsDialog(BuildContext context, {required String title, required List<Suggestion> suggestions}) {
  return showDialog<List<Suggestion>>(
    context: context,
    builder: (ctx) => _SuggestionsDialog(title: title, suggestions: suggestions),
  );
}

class _SuggestionsDialog extends StatefulWidget {
  const _SuggestionsDialog({required this.title, required this.suggestions});
  final String title;
  final List<Suggestion> suggestions;

  @override
  State<_SuggestionsDialog> createState() => _SuggestionsDialogState();
}

class _SuggestionsDialogState extends State<_SuggestionsDialog> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = widget.suggestions;
    final selected = items.where((s) => s.selected).length;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return AlertDialog(
      title: Text(widget.title),
      insetPadding: EdgeInsets.all(narrow ? 12 : 40),
      content: SizedBox(
        width: 560,
        child: items.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Nothing is missing. All values are filled in.'))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tick the values to fill in. Nothing changes until you press Apply.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (ctx, i) {
                      final s = items[i];
                      return CheckboxListTile(
                        value: s.selected,
                        onChanged: (v) => setState(() => s.selected = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Row(children: [
                          Expanded(child: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                          _ConfidencePill(s.confidence),
                        ]),
                        subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(s.detail)),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              ]),
      ),
      actions: [
        if (items.isNotEmpty)
          TextButton(
            onPressed: () => setState(() {
              final all = selected != items.length;
              for (final s in items) {
                s.selected = all;
              }
            }),
            child: Text(selected == items.length ? 'Untick all' : 'Tick all'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: selected == 0 ? null : () => Navigator.pop(context, items.where((s) => s.selected).toList()),
          child: Text('Apply $selected'),
        ),
      ],
    );
  }
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill(this.confidence);
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = confidence >= 0.8
        ? ('likely', const Color(0xFF2E7D32))
        : confidence >= 0.5
            ? ('probable', Colors.orange.shade800)
            : ('guess', Colors.grey.shade700);
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
