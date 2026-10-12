import 'package:flutter/material.dart';

import '../../api/client.dart' show ApiException;
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100915: the Compass home on the phone, the same three parts the web console draws (BI26092644): Focus (the
/// season line, the 60/30/10 mix with its prompts, the keystone habits by slot), Horizons (the goals, passed in) and
/// Review (passed in). The calendar is never computed here: the season line and the cycle key come from hub's
/// `GET /api/calendar/eq`, and the mix, source and prompts from `GET /api/cycle-theme?cycleKey=..&resolve=1`.

const compassParts = ['Focus', 'Horizons', 'Review'];

/// "Year 26 · Season 2 · Cycle 5 · Sprint 9", "Year 26 · Review cycle · Cycle 13 · Sprint 25", or the Stillweek line.
String eqHeaderLine(Map<String, dynamic> eq) {
  final year = fmt.s(eq['yearLabel']).isNotEmpty ? fmt.s(eq['yearLabel']) : fmt.s(eq['year']);
  if (eq['stillweek'] == true) return 'Year $year · the Stillweek, day ${fmt.s(eq['day'])}';
  final season = fmt.s(eq['season']).isEmpty ? 'Review cycle' : 'Season ${fmt.s(eq['season'])}';
  return 'Year $year · $season · Cycle ${fmt.s(eq['cycle'])} · Sprint ${fmt.s(eq['sprint'])}';
}

/// `eq2:26-C05` for a year and a cycle number, as vault stores cycle themes. Null while either is unknown.
String? cycleKeyOf(Map<String, dynamic> eq) {
  final year = eq['year'];
  final cycle = eq['cycle'];
  if (year is! num || cycle is! num) return null;
  final yy = (year.toInt() % 100).toString().padLeft(2, '0');
  final cc = cycle.toInt().toString().padLeft(2, '0');
  return 'eq2:$yy-C$cc';
}

/// The weights of a mix, one per named word, in order (primary, secondary, tertiary). Words without a weight get 0.
List<({String word, int weight})> mixParts(Map<String, dynamic> mix) {
  final words = [mix['primary'], mix['secondary'], mix['tertiary']].map(fmt.s).toList();
  final weights = (mix['weights'] is List) ? (mix['weights'] as List) : const [];
  final out = <({String word, int weight})>[];
  var w = 0;
  for (final word in words) {
    if (word.isEmpty) continue;
    out.add((word: word, weight: w < weights.length && weights[w] is num ? (weights[w] as num).round() : 0));
    w++;
  }
  return out;
}

/// What the mix card should offer, decided from what vault returned and how far into the cycle today is.
class MixPrompts {
  const MixPrompts({required this.emptyTenth, required this.chooseNext, required this.queuedWord, required this.held});
  final bool emptyTenth;

  /// Day 15 or later with a next cycle: ask for the word that enters at 10%.
  final bool chooseNext;
  final String? queuedWord;
  final bool held;
}

MixPrompts mixPrompts(Map<String, dynamic> cycle, int dayInCycle) {
  final next = fmt.m(cycle['next']);
  final queued = fmt.m(next['queued']);
  final late = next.isNotEmpty && next['cycleKey'] != null && dayInCycle >= 15;
  return MixPrompts(
    emptyTenth: cycle['needsTertiary'] == true,
    chooseNext: late,
    queuedWord: late && fmt.s(queued['word']).isNotEmpty ? fmt.s(queued['word']) : null,
    held: late && queued['hold'] == true,
  );
}

const habitStages = ['primary', 'secondary', 'tertiary', 'maintenance'];

/// Habits that carry a focus word, grouped by their derived stage; an unknown stage reads as maintenance.
/// Stages come back in the fixed order, and a stage with no habits is left out.
List<({String stage, List<Map<String, dynamic>> habits})> habitsByStage(List<Map<String, dynamic>> habits) {
  final by = <String, List<Map<String, dynamic>>>{};
  for (final h in habits) {
    if (fmt.s(h['focusWord']).isEmpty) continue;
    final s = fmt.s(h['stage']).toLowerCase();
    by.putIfAbsent(habitStages.contains(s) ? s : 'maintenance', () => []).add(h);
  }
  return [for (final s in habitStages) if (by[s] != null) (stage: s, habits: by[s]!)];
}

String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// The Focus part. [today] is for tests, so the date the habits are ticked against is fixed.
class CompassFocus extends StatefulWidget {
  const CompassFocus({super.key, this.today});
  final String? today;

  @override
  State<CompassFocus> createState() => _CompassFocusState();
}

class _CompassFocusState extends State<CompassFocus> {
  Map<String, dynamic>? _eq;
  Map<String, dynamic>? _cycle;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final snap = AppScope.of(context).store.rhythm;
      snap.hydrate().then((_) {
        if (mounted && snap.value == null) snap.refresh();
      });
      _load();
    });
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final eq = fmt.m(await api.getJson('/api/calendar/eq?date=${widget.today ?? _today()}'));
      if (!mounted) return;
      setState(() => _eq = eq);
      final key = cycleKeyOf(eq);
      if (key == null || eq['stillweek'] == true) return;
      final c = fmt.m(await api.getJson('/api/cycle-theme?cycleKey=${Uri.encodeQueryComponent(key)}&resolve=1'));
      if (!mounted) return;
      setState(() => _cycle = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _queue(String nextKey, {String? word, bool hold = false}) async {
    try {
      final r = await AppScope.of(context).api.postJson('/api/cycle-theme/queue', {
        'cycleKey': nextKey,
        'word': ?word,
        if (hold) 'hold': true,
      });
      if (fmt.m(r)['ok'] == false) throw Exception(fmt.s(fmt.m(r)['error']));
      if (mounted) toast(context, hold ? 'The primary focus stays one more cycle' : 'Queued');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, e.status == 409 ? 'That cycle already has a mix you set by hand, so nothing was queued.' : e.message, error: true);
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _askWord(String nextKey, String title) async {
    final c = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: T.title),
        content: TextField(key: const Key('compass-word'), controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'One word, for example Leverage')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
          FilledButton(key: const Key('compass-word-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Queue')),
        ],
      ),
    );
    final w = c.text.trim();
    if (go == true && w.isNotEmpty) await _queue(nextKey, word: w);
  }

  @override
  Widget build(BuildContext context) {
    final eq = _eq;
    final cycle = _cycle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (eq != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(eqHeaderLine(eq), key: const Key('compass-season'), style: T.mono)),
        if (_failed && eq == null) Text('The calendar did not answer.', style: T.small.copyWith(color: C.text3)),
        if (eq != null && eq['stillweek'] == true)
          const Panel(child: Text('The Stillweek belongs to no cycle: rest and review.')),
        if (cycle != null) _mixCard(cycle, eq ?? const {}),
        const SizedBox(height: 12),
        _habits(context),
      ],
    );
  }

  Widget _mixCard(Map<String, dynamic> cycle, Map<String, dynamic> eq) {
    final mix = fmt.m(cycle['mix']);
    final parts = mixParts(mix);
    final day = (eq['day'] is num) ? (eq['day'] as num).toInt() : 0;
    final p = mixPrompts(cycle, day);
    final source = fmt.s(cycle['source']);
    final nextKey = fmt.s(fmt.m(cycle['next'])['cycleKey']);
    final thisKey = cycleKeyOf(eq) ?? '';
    final colors = [C.green, C.amber, C.text3];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(parts.isEmpty ? 'No focus mix yet' : parts.first.word, style: T.w500(T.body2))),
            if (source.isNotEmpty) Badge2(source, color: C.greenBg, textColor: C.greenBright),
          ]),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  for (var i = 0; i < parts.length; i++)
                    Expanded(flex: parts[i].weight < 1 ? 1 : parts[i].weight, child: Container(key: Key('mix-seg-$i'), color: colors[i % colors.length])),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text([for (final x in parts) '${x.word} ${x.weight}%'].join('  ·  '), key: const Key('mix-line'), style: T.monoSmall),
          ],
          if (p.emptyTenth) ...[
            const SizedBox(height: 8),
            Text('The 10% slot is empty.', style: T.small.copyWith(color: C.text2)),
            TextButton(key: const Key('mix-fill-tenth'), onPressed: () => _askWord(thisKey, 'Fill the 10% slot'), child: const Text('Choose a word')),
          ],
          if (p.chooseNext) ...[
            const SizedBox(height: 8),
            Text(p.queuedWord != null ? 'Next cycle starts with ${p.queuedWord} at 10%.' : 'Pick the word that enters next cycle at 10%.', key: const Key('mix-next'), style: T.small.copyWith(color: C.text2)),
            Wrap(spacing: 8, children: [
              TextButton(key: const Key('mix-choose-next'), onPressed: () => _askWord(nextKey, 'The word that enters at 10%'), child: Text(p.queuedWord != null ? 'Change' : 'Choose a word')),
              if (!p.held) TextButton(key: const Key('mix-hold'), onPressed: () => _queue(nextKey, hold: true), child: const Text('Keep the primary one more cycle')),
            ]),
            if (p.held) Text('The primary focus is held for one more cycle.', key: const Key('mix-held'), style: T.small.copyWith(color: C.text3)),
          ],
        ],
      ),
    );
  }

  Widget _habits(BuildContext context) {
    final services = AppScope.of(context);
    final date = widget.today ?? _today();
    // Not a SnapshotView: this card sits inside the Planning view's own scroller, and a second one cannot be nested.
    final snap = services.store.rhythm;
    return ListenableBuilder(
      listenable: snap,
      builder: (context, _) {
        final data = snap.value;
        if (data == null) return const SizedBox.shrink();
        final map = fmt.m(data);
        final groups = habitsByStage(fmt.lm(map['habits']));
        final log = fmt.m(fmt.m(map['logs'])[date]);
        if (groups.isEmpty) {
          return const EmptyState('No keystone habits yet', 'A habit with a focus word shows here under its slot.', icon: Icons.bolt_rounded);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final g in groups) ...[
              SectionLabel(g.stage),
              for (final h in g.habits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Panel(
                    // A Row, not a CheckboxListTile: a ListTile inside a filled Panel asserts that its ink is hidden.
                    child: Row(
                      children: [
                        Checkbox(
                          key: Key('habit-${fmt.s(h['id'])}'),
                          value: fmt.b(log[fmt.s(h['id'])]),
                          onChanged: (v) async {
                            final res = await services.mutations.toggleHabit(date: date, habitId: fmt.s(h['id']), done: v ?? false);
                            if (!context.mounted) return;
                            if (!res.ok) toast(context, res.error!, error: true);
                          },
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fmt.s(h['title']), style: T.body2),
                              Text(fmt.s(h['focusWord']), style: T.monoSmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
