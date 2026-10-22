import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import 'codex.dart' show CodexControls, codexCell, codexVisibilityOf;

/// Journal: entries with mood/energy, streaks, add offline.
class JournalView extends StatelessWidget {
  const JournalView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SnapshotView(
          snapshot: services.store.journal,
          builder: (context, data) {
            final map = fmt.m(data);
            final entries = fmt.lm(map['entries']);
            final stats = fmt.m(map['stats']);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _stat('STREAK',
                            '${fmt.i(stats['streak'])}d', C.greenBright)),
                    const SizedBox(width: Sz.gap),
                    Expanded(
                        child: _stat('THIS WEEK',
                            '${fmt.i(stats['week'])}', C.cyan)),
                    const SizedBox(width: Sz.gap),
                    Expanded(
                        child: _stat(
                            'MOOD 7D',
                            fmt.dOrNull(stats['mood7']) == null
                                ? '-'
                                : fmt.d(stats['mood7']).toStringAsFixed(1),
                            C.amber)),
                  ],
                ),
                const SectionLabel('Entries'),
                if (entries.isEmpty)
                  const EmptyState(
                    'No entries yet',
                    'A journal the agent can reflect on. Write anything - '
                        'it works offline and syncs later.',
                    icon: Icons.auto_stories_rounded,
                  )
                else
                  ...entries.take(40).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _EntryTile(entry: e),
                      )),
              ],
            );
          },
        ),
        ViewFab(
          tooltip: 'Add a journal entry',
          icon: Icons.edit_rounded,
          onPressed: () => _addSheet(context),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.label),
          const SizedBox(height: 4),
          Text(value, style: T.headline.copyWith(color: color, fontSize: 16)),
        ],
      ),
    );
  }

  Future<void> _addSheet(BuildContext context) {
    final body = TextEditingController();
    final tags = TextEditingController();
    var mood = 6.0;
    var energy = 6.0;
    final services = AppScope.of(context);

    return showFormSheet(
      context,
      title: 'New entry',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(
                label: 'What happened?',
                controller: body,
                maxLines: 6,
                autofocus: true),
            _slider('Mood', mood, (v) => setSheet(() => mood = v)),
            _slider('Energy', energy, (v) => setSheet(() => energy = v)),
            Field(label: 'Tags (optional)', controller: tags, hint: 'comma,separated'),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () async {
                if (body.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final res = await services.mutations.addJournal(
                  body: body.text.trim(),
                  mood: mood.round(),
                  energy: energy.round(),
                  tags: tags.text.trim(),
                );
                if (!context.mounted) return;
                if (!res.ok) {
                  toast(context, res.error!, error: true);
                } else if (res.queued) {
                  toast(context, 'Entry saved locally - will sync');
                }
              },
              child: const Text('Save entry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
      String label, double value, void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(),
                style: T.label.copyWith(letterSpacing: 0.6)),
            const Spacer(),
            Text('${value.round()}/10',
                style: T.mono.copyWith(color: C.greenBright)),
          ],
        ),
        Slider(
            value: value, min: 1, max: 10, divisions: 9, onChanged: onChanged),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final queued = fmt.s(entry['ID']) == 'QUEUED';
    final visibility = codexVisibilityOf(entry['VISIBILITY']);
    return Panel(
      onTap: queued ? null : () => _detail(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(fmt.shortDate(entry['DATE']),
                  style: T.mono.copyWith(color: C.greenBright)),
              const SizedBox(width: 8),
              if (fmt.s(entry['MOOD']).isNotEmpty)
                Badge2('mood ${fmt.s(entry['MOOD'])}',
                    color: C.surface, textColor: C.text3),
              const SizedBox(width: 4),
              if (fmt.s(entry['ENERGY']).isNotEmpty)
                Badge2('energy ${fmt.s(entry['ENERGY'])}',
                    color: C.surface, textColor: C.text3),
              const Spacer(),
              if (visibility != 'private') Badge2(visibility, color: C.cyanBg, textColor: C.cyan),
              if (queued)
                const Badge2('queued', color: C.amberBg, textColor: C.amber),
            ],
          ),
          const SizedBox(height: 8),
          Text(fmt.s(entry['BODY']), style: T.body2.copyWith(height: 1.55)),
          if (fmt.s(entry['AI_NOTE']).isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: C.greenBg2,
                borderRadius: BorderRadius.circular(Sz.rSm),
                border: Border.all(color: C.greenDim.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 13, color: C.greenBright),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(fmt.s(entry['AI_NOTE']),
                          style: T.small.copyWith(color: C.text2))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// BI26092651: the entry in full, with its Codex controls (visibility, practices, the Codex id once minted).
  void _detail(BuildContext context) {
    final services = AppScope.of(context);
    showFormSheet(
      context,
      title: fmt.shortDate(entry['DATE']),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(fmt.s(entry['BODY']), style: T.body2.copyWith(height: 1.55)),
          ),
          KvRow('ID', fmt.s(entry['ID']), mono: true),
          if (codexCell(entry['TAGS']).isNotEmpty) KvRow('Tags', codexCell(entry['TAGS'])),
          const SizedBox(height: 14),
          CodexControls(
            row: entry,
            onSave: (fields) async {
              final res = await services.mutations.updateJournal(fmt.s(entry['ID']), fields);
              if (!context.mounted) return res.ok;
              if (!res.ok) {
                toast(context, res.error ?? 'Could not save', error: true);
              } else if (res.queued) {
                toast(context, 'Queued - will sync');
              }
              return res.ok;
            },
          ),
        ],
      ),
    );
  }
}