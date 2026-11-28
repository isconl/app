import 'package:flutter/material.dart';

import 'client.dart';
import 'loader.dart';
import 'rows_models.dart';
import 'rows_views.dart';
import 'tokens.dart';

/// Rows waiting on Sconl's call. Tap one to read its options and answer.
class DecisionsView extends StatelessWidget {
  const DecisionsView({super.key, required this.client, required this.stepUp});
  final SlateClient client;
  final WriteStepUp stepUp;

  @override
  Widget build(BuildContext context) => Loader<List<RowSummary>>(
        load: client.decisions,
        builder: (context, rows, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('${rows.length} waiting', style: TextStyle(color: SlateTokens.of(context).text2, fontSize: 12)),
              const SizedBox(height: 8),
              for (var i = 0; i < rows.length; i++)
                RowTile(
                  id: 'Decision ${i + 1} of ${rows.length}: ${rows[i].id}',
                  title: rows[i].title,
                  meta: rows[i].project,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => DecisionScreen(
                          client: client, stepUp: stepUp, row: rows[i], position: i + 1, of: rows.length),
                    ));
                    reload();
                  },
                ),
            ],
          ),
        ),
      );
}

/// One decision: the row's written options, an answer field, and Record.
class DecisionScreen extends StatefulWidget {
  const DecisionScreen({
    super.key,
    required this.client,
    required this.stepUp,
    required this.row,
    required this.position,
    required this.of,
  });

  final SlateClient client;
  final WriteStepUp stepUp;
  final RowSummary row;
  final int position;
  final int of;

  @override
  State<DecisionScreen> createState() => _DecisionScreenState();
}

class _DecisionScreenState extends State<DecisionScreen> {
  final _answer = TextEditingController();
  late final Future<RowDetail> _detail = widget.client.row(widget.row.id, widget.row.project);
  String? _message;
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final summary = 'Record your answer on ${widget.row.id}';
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await widget.stepUp(summary)) {
        setState(() => _message = 'Step-up was not completed. Nothing was recorded.');
        return;
      }
      await widget.client.answerDecision(widget.row.id, widget.row.project, _answer.text.trim());
      setState(() {
        _done = true;
        _message = 'Recorded on ${widget.row.id}.';
      });
    } catch (e) {
      setState(() => _message = 'Could not record: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Decision ${widget.position} of ${widget.of}')),
      body: FutureBuilder<RowDetail>(
        future: _detail,
        builder: (context, snap) {
          final r = snap.data;
          if (snap.hasError) return Center(child: Text('Could not reach slate.', style: TextStyle(color: t.danger)));
          if (r == null) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(r.title, style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SelectableText(r.body, style: TextStyle(color: t.text2, fontSize: 13, height: 1.45)),
            const SizedBox(height: 16),
            TextField(
              key: const Key('answer-field'),
              controller: _answer,
              minLines: 2,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Your answer', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('record-button'),
              onPressed: _busy || _done || _answer.text.trim().isEmpty ? null : _record,
              child: const Text('Record answer'),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!, key: const Key('decision-message'), style: TextStyle(color: t.text2, fontSize: 13)),
              ),
          ]);
        },
      ),
    );
  }
}

/// Rows gated for a brainstorm. Read-only here: a brainstorm is a live
/// conversation in a session, so the phone shows what is waiting.
class BrainstormsView extends StatelessWidget {
  const BrainstormsView({super.key, required this.client, required this.stepUp});
  final SlateClient client;
  final WriteStepUp stepUp;

  @override
  Widget build(BuildContext context) => Loader<List<RowSummary>>(
        load: client.brainstorms,
        builder: (context, rows, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('${rows.length} waiting for a brainstorm session',
                  style: TextStyle(color: SlateTokens.of(context).text2, fontSize: 12)),
              const SizedBox(height: 8),
              for (final r in rows)
                RowTile(
                  id: r.id,
                  title: r.title,
                  meta: r.project,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => RowDetailScreen(client: client, stepUp: stepUp, id: r.id, project: r.project),
                  )),
                ),
            ],
          ),
        ),
      );
}
