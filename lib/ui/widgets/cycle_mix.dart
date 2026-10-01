import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import 'common.dart';

/// BI26092508: this cycle's and next cycle's focus mix, primary/secondary/
/// tertiary words weighted 60/30/10 by default, edited from Planning.
///
/// Reads and writes GET/POST /api/cycle-theme (vault). `theme` in that
/// response is always the primary word, which is what the header and the
/// calendar show; the full mix only appears here.
class CycleMixCard extends StatefulWidget {
  const CycleMixCard({super.key});

  @override
  State<CycleMixCard> createState() => _CycleMixCardState();
}

/// The default 13-word rotation, same order as the web's
/// getEquicycleContext() and calendar.dart's _EqContext.
const _rotation = [
  'Plant', 'Push', 'Climb', 'Reap', 'Dig', 'Weave', 'Mend', 'Scout',
  'Scale', 'Make', 'Run', 'Stock', 'Audit',
];

class _CycleRef {
  _CycleRef(this.eqYear, this.cycleNum);
  final int eqYear;
  final int cycleNum;
  String get key => '$eqYear-$cycleNum';
  String get defaultWord => _rotation[(cycleNum - 1).clamp(0, 12)];
  _CycleRef get next =>
      cycleNum >= 13 ? _CycleRef(eqYear + 1, 1) : _CycleRef(eqYear, cycleNum + 1);

  /// The equicycle year starts on the first Sunday of June (calendar.dart).
  /// BI26092521: eqYear is the year of the most recent first-Sunday-of-June
  /// on or before today, not simply "this year from June, else last year" --
  /// kept in step with calendar.dart's _EqContext and the web/pulse copies.
  static DateTime _firstSundayOfJune(int year) {
    final june1 = DateTime(year, 6, 1);
    final daysAhead = (7 - june1.weekday % 7) % 7;
    return DateTime(year, 6, 1 + daysAhead);
  }

  static _CycleRef today() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var eqYear = today.year;
    if (today.isBefore(_firstSundayOfJune(eqYear))) eqYear -= 1;
    final start = _firstSundayOfJune(eqYear);
    final days = today.difference(start).inDays;
    return _CycleRef(eqYear, (days < 0 ? 0 : days) ~/ 28 + 1);
  }
}

/// The `<eqYear>-<cycle>` key of today's cycle, as `/api/cycle-theme?cycleKey=` takes it.
String currentCycleKey() => _CycleRef.today().key;

class _Mix {
  _Mix(this.words, this.weights, this.tagline);
  final List<String> words;
  final List<int> weights;
  final String? tagline;

  static _Mix? from(dynamic res) {
    final m = res is Map ? res['mix'] : null;
    if (m is! Map) return null;
    final words = [m['primary'], m['secondary'], m['tertiary']]
        .whereType<String>()
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return null;
    final raw = m['weights'];
    final weights = raw is List ? raw.map((n) => (n as num).toInt()).toList() : <int>[];
    return _Mix(
      words,
      weights.length == words.length ? weights : [for (final _ in words) 100 ~/ words.length],
      m['tagline'] is String && (m['tagline'] as String).isNotEmpty ? m['tagline'] as String : null,
    );
  }
}

class _CycleMixCardState extends State<CycleMixCard> {
  final _mixes = <String, _Mix?>{};
  final _loaded = <String>{};
  late final _CycleRef _now = _CycleRef.today();

  static const _tones = [C.green, C.amber, Color(0xFF58A6FF)];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final c in [_now, _now.next]) {
      _load(c.key);
    }
  }

  Future<void> _load(String key) async {
    if (_loaded.contains(key)) return;
    _loaded.add(key);
    try {
      final res = await AppScope.of(context).api.getJson('/api/cycle-theme?cycleKey=$key');
      if (mounted) setState(() => _mixes[key] = _Mix.from(res));
    } catch (_) {
      // Offline: the card shows the default word until the next load.
    }
  }

  Future<void> _save(String key, Map<String, dynamic> body) async {
    try {
      final res = await AppScope.of(context).api.postJson('/api/cycle-theme', {'cycleKey': key, ...body});
      if (!mounted) return;
      setState(() => _mixes[key] = _Mix.from(res));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _edit(_CycleRef c) {
    final m = _mixes[c.key];
    final primary = TextEditingController(text: m != null ? m.words[0] : '');
    final secondary = TextEditingController(text: m != null && m.words.length > 1 ? m.words[1] : '');
    final tertiary = TextEditingController(text: m != null && m.words.length > 2 ? m.words[2] : '');
    final weights = TextEditingController(text: (m?.weights ?? const [60, 30, 10]).join(', '));
    final tagline = TextEditingController(text: m?.tagline ?? '');
    return showFormSheet(
      context,
      title: 'Focus mix, cycle ${c.cycleNum}',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(label: 'Primary focus (e.g. ${c.defaultWord})', controller: primary, autofocus: true),
          Field(label: 'Secondary (optional)', controller: secondary),
          Field(label: 'Tertiary (optional)', controller: tertiary),
          Field(label: 'Weights, summing to 100', controller: weights),
          Field(label: 'Tagline (optional)', controller: tagline),
          FilledButton(
            onPressed: () {
              final words = [primary.text, secondary.text, tertiary.text]
                  .map((w) => w.trim())
                  .where((w) => w.isNotEmpty)
                  .toList();
              final body = <String, dynamic>{
                'primary': primary.text.trim(),
                'secondary': secondary.text.trim().isEmpty ? null : secondary.text.trim(),
                'tertiary': tertiary.text.trim().isEmpty ? null : tertiary.text.trim(),
                'tagline': tagline.text.trim().isEmpty ? null : tagline.text.trim(),
              };
              if (words.isNotEmpty) {
                final w = weights.text
                    .split(RegExp(r'[,/\s]+'))
                    .where((s) => s.isNotEmpty)
                    .map(int.tryParse)
                    .toList();
                if (w.length == words.length && !w.contains(null)) {
                  body['weights'] = w;
                } else if (words.length == 1) {
                  body['weights'] = [100];
                } else {
                  toast(ctx, 'Weights need one number per word (${words.length})', error: true);
                  return;
                }
              }
              Navigator.pop(ctx);
              _save(c.key, body);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _bar(_Mix? m, String fallback) {
    final words = m?.words ?? [fallback];
    final weights = m?.weights ?? [100];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var i = 0; i < words.length; i++)
                  if (weights[i] > 0)
                    Expanded(
                      flex: weights[i],
                      child: Container(color: _tones[i].withValues(alpha: 0.8)),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (var i = 0; i < words.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: _tones[i], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${words[i]} ${weights[i]}%', style: T.small.copyWith(color: C.text2)),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, _CycleRef c) {
    final m = _mixes[c.key];
    final word = m?.words.first ?? c.defaultWord;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$label · cycle ${c.cycleNum}', style: T.monoSmall),
              const SizedBox(width: 10),
              Text(word.toUpperCase(), style: T.w500(T.body2).copyWith(color: C.greenBright)),
              const Spacer(),
              TextButton(onPressed: () => _edit(c), child: const Text('Set mix')),
              if (m != null)
                TextButton(
                  onPressed: () => _save(c.key, {'theme': ''}),
                  child: const Text('Revert'),
                ),
            ],
          ),
          if (m?.tagline != null) Text(m!.tagline!, style: T.small.copyWith(color: C.text3)),
          const SizedBox(height: 6),
          _bar(m, word),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cycle focus', style: T.w500(T.body2)),
          _row('This cycle', _now),
          _row('Next cycle', _now.next),
        ],
      ),
    );
  }
}
