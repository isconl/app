import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Spark: the idea pipeline.
///
/// Capture is the reason this view exists on a phone at all - an idea arrives
/// away from the desk or it does not arrive. Everything else here (staging,
/// scoring, filtering) is review work that happens to also be pleasant on a
/// phone, but the FAB is the point.
class IdeasView extends StatefulWidget {
  const IdeasView({super.key});

  @override
  State<IdeasView> createState() => _IdeasViewState();
}

class _IdeasViewState extends State<IdeasView> {
  String _stage = 'all';

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Stack(
      children: [
        SnapshotView(
          snapshot: services.store.ideas,
          builder: (context, data) {
            final map = fmt.m(data);
            final all = fmt.lm(map['ideas'])
                .where((i) => fmt.s(i['STATUS']) != 'dropped')
                .toList();
            final stats = fmt.m(map['stats']);
            final stages = fmt.l(map['stages']).map(fmt.s).toList();

            final shown = _stage == 'all'
                ? all
                : all.where((i) => fmt.s(i['STAGE']) == _stage).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _stat('OPEN', '${fmt.i(stats['open'])}',
                            C.greenBright)),
                    const SizedBox(width: Sz.gap),
                    Expanded(
                        child: _stat(
                            'AGENT', '${fmt.i(stats['agent'])}', C.cyan)),
                    const SizedBox(width: Sz.gap),
                    Expanded(
                        child: _stat('SHIPPED', '${fmt.i(stats['shipped'])}',
                            C.violet)),
                  ],
                ),
                if (stages.isNotEmpty) ...[
                  const SectionLabel('Stage'),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Pill('all',
                            selected: _stage == 'all',
                            onTap: () => setState(() => _stage = 'all')),
                        for (final st in stages) ...[
                          const SizedBox(width: 6),
                          Pill(st,
                              selected: _stage == st,
                              onTap: () => setState(() => _stage = st)),
                        ],
                      ],
                    ),
                  ),
                ],
                const SectionLabel('Ideas'),
                if (shown.isEmpty)
                  const EmptyState(
                    'Nothing captured here yet',
                    'Tap + to record one. It works offline and files itself '
                        'when the agent next hears from you.',
                    icon: Icons.lightbulb_outline_rounded,
                  )
                else
                  ...shown.take(60).map((idea) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _IdeaTile(
                          idea: idea,
                          stages: stages,
                          onStage: (next) => _setStage(idea, next),
                        ),
                      )),
              ],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            backgroundColor: C.greenDim,
            foregroundColor: Colors.white,
            onPressed: () => _captureSheet(context),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _setStage(Map<String, dynamic> idea, String stage) async {
    final services = AppScope.of(context);
    final res = await services.mutations
        .updateIdea(fmt.s(idea['ID']), {'stage': stage});
    if (!mounted) return;
    if (!res.ok) {
      toast(context, res.error!, error: true);
    } else if (res.queued) {
      toast(context, 'Queued - will sync');
    }
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

  Future<void> _captureSheet(BuildContext context) {
    final title = TextEditingController();
    final body = TextEditingController();
    final domain = TextEditingController();
    final tags = TextEditingController();
    var type = 'personal';
    final services = AppScope.of(context);

    return showFormSheet(
      context,
      title: 'Capture an idea',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(
                label: 'The idea',
                controller: title,
                hint: 'One line is enough',
                autofocus: true),
            Field(
                label: 'More, if you have it',
                controller: body,
                maxLines: 4,
                hint: 'Optional - the agent enriches this later'),
            Segmented(
              label: 'Type',
              options: const ['personal', 'agent', 'venture', 'work'],
              value: type,
              onChanged: (v) => setSheet(() => type = v),
            ),
            Field(label: 'Domain', controller: domain, hint: 'optional'),
            Field(label: 'Tags', controller: tags, hint: 'comma,separated'),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final res = await services.mutations.addIdea(
                  title: title.text.trim(),
                  body: body.text.trim(),
                  domain: domain.text.trim(),
                  tags: tags.text.trim(),
                  type: type,
                );
                if (!context.mounted) return;
                if (!res.ok) {
                  toast(context, res.error!, error: true);
                } else if (res.queued) {
                  toast(context, 'Captured locally - will sync');
                } else {
                  toast(context, 'Captured');
                }
              },
              child: const Text('Capture'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeaTile extends StatelessWidget {
  const _IdeaTile(
      {required this.idea, required this.stages, required this.onStage});
  final Map<String, dynamic> idea;
  final List<String> stages;
  final void Function(String) onStage;

  @override
  Widget build(BuildContext context) {
    final queued = fmt.s(idea['ID']) == 'QUEUED';
    final stage = fmt.s(idea['STAGE']);
    final impact = fmt.s(idea['IMPACT']);
    final effort = fmt.s(idea['EFFORT']);
    final body = fmt.s(idea['BODY']);

    return Panel(
      onTap: queued ? null : () => _detail(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (stage.isNotEmpty)
                Badge2(stage, color: C.cyanBg, textColor: C.cyan),
              const SizedBox(width: 6),
              if (fmt.s(idea['TYPE']).isNotEmpty)
                Badge2(fmt.s(idea['TYPE'])),
              const Spacer(),
              if (queued)
                const Badge2('queued', color: C.amberBg, textColor: C.amber)
              else
                Text(fmt.ago(idea['CREATED_AT']), style: T.monoSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(fmt.s(idea['TITLE']),
              style: T.w600(T.body.copyWith(color: C.text))),
          if (body.isNotEmpty && body != '-') ...[
            const SizedBox(height: 5),
            Text(fmt.truncate(body, 160),
                style: T.small.copyWith(color: C.text3)),
          ],
          if (impact.isNotEmpty && impact != '-' ||
              effort.isNotEmpty && effort != '-') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (impact.isNotEmpty && impact != '-')
                  Badge2('impact $impact',
                      color: C.greenBg, textColor: C.greenBright),
                const SizedBox(width: 6),
                if (effort.isNotEmpty && effort != '-')
                  Badge2('effort $effort'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _detail(BuildContext context) {
    final body = fmt.s(idea['BODY']);
    final note = fmt.s(idea['NOTE']);
    showFormSheet(
      context,
      title: fmt.truncate(fmt.s(idea['TITLE']), 60),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (body.isNotEmpty && body != '-')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(body, style: T.body2.copyWith(height: 1.55)),
            ),
          if (note.isNotEmpty && note != '-')
            Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                      child: Text(note,
                          style: T.small.copyWith(color: C.text2))),
                ],
              ),
            ),
          KvRow('ID', fmt.s(idea['ID']), mono: true),
          KvRow('Domain', fmt.s(idea['DOMAIN'])),
          KvRow('Tags', fmt.s(idea['TAGS'])),
          KvRow('Captured', fmt.shortDate(idea['CREATED_AT'])),
          const SizedBox(height: 14),
          Text('MOVE TO STAGE', style: T.label.copyWith(letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final st in stages)
                Pill(st,
                    selected: st == fmt.s(idea['STAGE']),
                    onTap: () {
                      Navigator.pop(ctx);
                      onStage(st);
                    }),
            ],
          ),
        ],
      ),
    );
  }
}
