import 'package:flutter/material.dart';

import 'client.dart';
import 'loader.dart';
import 'rows_models.dart';
import 'tokens.dart';

const rowTypes = ['plan', 'build', 'work', 'light', 'content'];

String _meta(RowSummary r) => [
      r.project,
      r.type + (r.subset != null ? ' · ${r.subset}' : ''),
      r.status,
      if (r.isClaimed) 'claimed by ${r.claimedBy}',
      if (r.gate != null) 'gate ${r.gate}',
    ].join(' · ');

/// The live rows with a type filter. Tap a row for its detail.
class RowsView extends StatefulWidget {
  const RowsView({super.key, required this.client, required this.stepUp});
  final SlateClient client;
  final WriteStepUp stepUp;

  @override
  State<RowsView> createState() => _RowsViewState();
}

class _RowsViewState extends State<RowsView> {
  String? _type;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 44,
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          for (final t in [null, ...rowTypes])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('type-${t ?? 'all'}'),
                label: Text(t ?? 'all'),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
              ),
            ),
        ])),
      ),
      Expanded(
        child: Loader<List<RowSummary>>(
          key: ValueKey(_type),
          load: () => widget.client.rows(type: _type),
          builder: (context, rows, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (rows.isEmpty) const Text('No live rows.'),
                for (final r in rows)
                  RowTile(
                    id: r.id,
                    title: r.title,
                    meta: _meta(r),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => RowDetailScreen(
                            client: widget.client, stepUp: widget.stepUp, id: r.id, project: r.project),
                      ));
                      reload();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

/// One row in full, with claim, close and edit. Each write reads back what it
/// will do, passes step-up, then runs.
class RowDetailScreen extends StatefulWidget {
  const RowDetailScreen({
    super.key,
    required this.client,
    required this.stepUp,
    required this.id,
    required this.project,
  });

  final SlateClient client;
  final WriteStepUp stepUp;
  final String id;
  final String project;

  @override
  State<RowDetailScreen> createState() => _RowDetailScreenState();
}

class _RowDetailScreenState extends State<RowDetailScreen> {
  late Future<RowDetail> _row = widget.client.row(widget.id, widget.project);
  String? _message;
  bool _busy = false;

  Future<void> _write(String summary, Future<void> Function() run) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await widget.stepUp(summary)) {
        setState(() => _message = 'Step-up was not completed. Nothing was changed.');
        return;
      }
      await run();
      setState(() {
        _row = widget.client.row(widget.id, widget.project);
        _message = 'Done: $summary';
      });
    } catch (e) {
      setState(() => _message = 'Could not do that: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _ask(String title, {String initial = '', int lines = 3}) async {
    final out = await showDialog<String>(
      context: context,
      builder: (_) => _AskDialog(title: title, initial: initial, lines: lines),
    );
    return (out == null || out.isEmpty) ? null : out;
  }
  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.id)),
      body: FutureBuilder<RowDetail>(
        future: _row,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not reach slate.', style: TextStyle(color: t.danger)));
          final r = snap.data;
          if (r == null) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(r.title, style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(_meta(r), style: TextStyle(color: t.text3, fontSize: 12)),
            const SizedBox(height: 14),
            SelectableText(r.body, style: TextStyle(color: t.text2, fontSize: 13, height: 1.45)),
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                key: const Key('claim-button'),
                onPressed: _busy || r.isClaimed
                    ? null
                    : () => _write('Claim ${r.id}', () => widget.client.claimRow(r.id, r.project)),
                child: const Text('Claim'),
              ),
              OutlinedButton(
                key: const Key('edit-button'),
                onPressed: _busy
                    ? null
                    : () async {
                        final title = await _ask('New title', initial: r.title, lines: 1);
                        if (title == null) return;
                        await _write('Retitle ${r.id} to "$title"',
                            () => widget.client.editRow(r.id, r.project, title: title));
                      },
                child: const Text('Edit title'),
              ),
              FilledButton(
                key: const Key('close-button'),
                onPressed: _busy
                    ? null
                    : () async {
                        final note = await _ask('Close note (what shipped, with evidence)');
                        if (note == null) return;
                        await _write('Close ${r.id}', () => widget.client.closeRow(r.id, r.project, note));
                      },
                child: const Text('Close'),
              ),
            ]),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!, key: const Key('row-message'), style: TextStyle(color: t.text2, fontSize: 13)),
              ),
          ]);
        },
      ),
    );
  }
}

class _AskDialog extends StatefulWidget {
  const _AskDialog({required this.title, required this.initial, required this.lines});
  final String title;
  final String initial;
  final int lines;

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(key: const Key('dialog-field'), controller: _c, minLines: widget.lines, maxLines: 8, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('dialog-ok'), onPressed: () => Navigator.pop(context, _c.text.trim()), child: const Text('Continue')),
        ],
      );
}