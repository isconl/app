import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/spaced_review.dart';
import '../widgets/common.dart';
import 'learning.dart' show LessonScreen;

/// The module text for a review item, from the offline cache first.
Future<String> lessonContent(AppServices services, ReviewItem item) async {
  final snap = services.store.detail(
    'lesson',
    item.key,
    '/api/learning/lesson?course=${Uri.encodeComponent(item.course)}&file=${Uri.encodeComponent(item.file)}',
  );
  await snap.hydrate();
  return fmt.s(fmt.m(snap.value)['content']);
}

/// BI26100145: the Today card. Shows only when a module is due.
class ReviewCard extends StatefulWidget {
  const ReviewCard({super.key});

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  int? _questions;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    SpacedReview.instance.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await SpacedReview.instance.ensureLoaded(AppScope.of(context).db);
      if (mounted) _count();
    });
  }

  @override
  void dispose() {
    SpacedReview.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) _count();
  }

  Future<void> _count() async {
    final services = AppScope.of(context);
    final due = dueToday(SpacedReview.instance.items, DateTime.now());
    final sig = due.map((d) => '${d.key}:${d.step}:${fmt.isoDate(d.due)}').join(',');
    if (sig == _signature) return;
    _signature = sig;
    var total = 0;
    for (final item in due) {
      final c = await lessonContent(services, item);
      total += extractQuestions(c).take(maxQuestionsPerModule).length;
    }
    if (mounted) setState(() => _questions = due.isEmpty ? null : total);
  }

  @override
  Widget build(BuildContext context) {
    final due = dueToday(SpacedReview.instance.items, DateTime.now());
    if (due.isEmpty) return const SizedBox.shrink();
    final q = _questions;
    final text = q == null || q == 0 ? 'Review: ${due.length} module${due.length == 1 ? '' : 's'} due' : reviewSummary(q);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        key: const Key('review-card'),
        onTap: () async {
          await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const SpacedReviewScreen()));
          if (mounted) {
            _signature = '';
            _count();
          }
        },
        child: Row(children: [
          const Icon(Icons.replay_rounded, size: 18, color: C.green),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: T.body2.copyWith(color: C.text))),
          const Icon(Icons.chevron_right_rounded, size: 18, color: C.text3),
        ]),
      ),
    );
  }
}

class _Ask {
  _Ask(this.item, this.question);
  final ReviewItem item;
  final String question;
  bool? got;
}

/// The review itself: one question at a time. Nothing here has an answer key,
/// because a PROBE is an open question, so the user grades themselves: read the
/// passage if needed, then Got it or Missed. A module with any miss comes back
/// in 3 days; a clean round moves it on.
class SpacedReviewScreen extends StatefulWidget {
  const SpacedReviewScreen({super.key, this.now});

  /// Replaced in tests.
  final DateTime? now;

  @override
  State<SpacedReviewScreen> createState() => _SpacedReviewScreenState();
}

class _SpacedReviewScreenState extends State<SpacedReviewScreen> {
  List<_Ask>? _asks;
  var _index = 0;
  var _finished = false;
  final _outcome = <String, bool>{};

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _build());
  }

  Future<void> _build() async {
    final services = AppScope.of(context);
    await SpacedReview.instance.ensureLoaded(services.db);
    final asks = <_Ask>[];
    for (final item in dueToday(SpacedReview.instance.items, _now)) {
      final qs = pickQuestions(extractQuestions(await lessonContent(services, item)), last: item.last);
      if (qs.isEmpty) {
        // Nothing to test in this module: it counts as a clean round rather than staying due forever.
        await SpacedReview.instance.record(item.key, perfect: true, now: _now, db: services.db);
        continue;
      }
      asks.addAll([for (final q in qs) _Ask(item, q)]);
    }
    if (!mounted) return;
    setState(() {
      _asks = asks;
      _finished = asks.isEmpty;
    });
  }

  Future<void> _answer(bool got) async {
    final asks = _asks!;
    asks[_index].got = got;
    if (_index + 1 < asks.length) {
      setState(() => _index++);
      return;
    }
    final services = AppScope.of(context);
    final byItem = <String, List<_Ask>>{};
    for (final a in asks) {
      byItem.putIfAbsent(a.item.key, () => []).add(a);
    }
    for (final e in byItem.entries) {
      final perfect = e.value.every((a) => a.got == true);
      _outcome[e.key] = perfect;
      await SpacedReview.instance.record(e.key,
          perfect: perfect, now: _now, asked: [for (final a in e.value) a.question], db: services.db);
    }
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final asks = _asks;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(title: const Text('Review')),
      body: asks == null
          ? const Center(child: MiniSpinner(size: 22))
          : _finished
              ? _done()
              : _question(asks),
    );
  }

  Widget _question(List<_Ask> asks) {
    final a = asks[_index];
    return ListView(padding: const EdgeInsets.all(18), children: [
      Text('Question ${_index + 1} of ${asks.length}', style: T.label),
      const SizedBox(height: 8),
      Text(a.item.title, style: T.tiny),
      const SizedBox(height: 12),
      Text(a.question, key: const Key('review-question'), style: T.body.copyWith(color: C.text, height: 1.6)),
      const SizedBox(height: 18),
      OutlinedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => LessonScreen(course: a.item.course, file: a.item.file, title: a.item.title, status: 'done')),
        ),
        child: const Text('Open the passage'),
      ),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: OutlinedButton(key: const Key('review-missed'), onPressed: () => _answer(false), child: const Text('Missed'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(key: const Key('review-got'), onPressed: () => _answer(true), child: const Text('Got it'))),
      ]),
    ]);
  }

  Widget _done() {
    final items = SpacedReview.instance.items;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Text(_outcome.isEmpty ? 'Nothing to review today.' : 'Review done.', style: T.title),
      const SizedBox(height: 12),
      for (final e in _outcome.entries)
        Builder(builder: (_) {
          final item = items.firstWhere((i) => i.key == e.key);
          final line = item.retired
              ? 'retired from the schedule'
              : e.value
                  ? 'next review ${fmt.shortDate(fmt.isoDate(item.due))}'
                  : 'back in $missRetryDays days';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              child: Row(children: [
                Icon(e.value ? Icons.check_circle_outline_rounded : Icons.refresh_rounded, size: 18, color: e.value ? C.green : C.amber),
                const SizedBox(width: 10),
                Expanded(child: Text('${item.title}: $line', style: T.small.copyWith(color: C.text))),
              ]),
            ),
          );
        }),
      const SizedBox(height: 12),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
    ]);
  }
}
