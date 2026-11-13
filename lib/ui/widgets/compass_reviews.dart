import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100136 (Equicycle 2, 5/5): Compass keyed to the season and the year, on the phone. A season review is offered from the
/// last day of C03, C06, C09 and C12 (and stays open); C13, the Audit cycle, opens the year review with the four season
/// reviews side by side and sets next year's first mix. Where today sits in the year comes from the calendar service through
/// scope's `/compass/review`, which hub serves as `/api/compass/review`; this draws what it is given.

String _cc(int n) => 'C${n.toString().padLeft(2, '0')}';

/// `C04: Plant 67 / Make 33`, or `C05: no mix set`.
String reviewMixLine(Map<String, dynamic> m) {
  final key = fmt.s(m['cycleKey']);
  final tag = key.length >= 3 ? key.substring(key.length - 3) : key;
  final x = fmt.m(m['mix']);
  if (x.isEmpty) return '$tag: no mix set';
  final weights = x['weights'] is List ? (x['weights'] as List) : const [];
  final words = [for (final k in ['primary', 'secondary', 'tertiary']) if (fmt.s(x[k]).isNotEmpty) fmt.s(x[k])];
  return '$tag: ${[for (var i = 0; i < words.length; i++) '${words[i]} ${i < weights.length ? weights[i] : ''}'.trim()].join(' / ')}';
}

class CompassReviews extends StatefulWidget {
  const CompassReviews({super.key});

  @override
  State<CompassReviews> createState() => _CompassReviewsState();
}

class _CompassReviewsState extends State<CompassReviews> {
  Future<dynamic>? _future;
  dynamic _last; // the last answer, kept on screen while a refresh is in flight so the form does not blink away
  final _text = <String, TextEditingController>{};

  TextEditingController _c(String id, String initial) => _text.putIfAbsent(id, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _reload() {
    final f = AppScope.of(context).api.getJson('/api/compass/review');
    setState(() {
      _future = f;
    });
  }

  Future<void> _post(String path, Map<String, dynamic> body, String ok) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppScope.of(context).api.postJson(path, body);
      messenger.showSnackBar(SnackBar(content: Text(ok)));
      for (final k in ['np', 'ns', 'nt']) {
        _text[k]?.clear();
      }
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save the review')));
    }
  }

  @override
  Widget build(BuildContext context) {
    _future ??= AppScope.of(context).api.getJson('/api/compass/review');
    return FutureBuilder<dynamic>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) _last = snap.data;
        if (_last == null) return const SizedBox.shrink(); // Reviews are an addition to Compass: loading or an outage must not hide the page.
        final d = fmt.m(_last);
        if (d['available'] != true) {
          return Panel(
            margin: const EdgeInsets.only(bottom: 12),
            child: Text(fmt.s(d['reason']).isEmpty ? 'Reviews: the calendar service did not answer.' : 'Reviews: ${fmt.s(d['reason'])}', style: T.tiny.copyWith(color: C.text3)),
          );
        }
        final pos = fmt.m(d['position']);
        final year = fmt.d(pos['year']).toInt();
        final cycle = pos['cycle'] is num ? (pos['cycle'] as num).toInt() : null;
        final stillweek = pos['stillweek'] == true;
        final seasons = fmt.lm(d['seasons']).map(fmt.m).toList();
        final offered = seasons.where((s) => s['offered'] == true).toList();
        final yr = fmt.m(d['year']);
        final current = cycle == null ? null : ((cycle - 1) ~/ 3) + 1;
        final waiting = !stillweek && cycle != null && cycle <= 12 && current != null && seasons.every((s) => fmt.d(s['season']).toInt() != current || s['offered'] != true);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (waiting)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Season $current review opens on the last day of ${_cc(current * 3)}.', key: const Key('review-waiting'), style: T.tiny.copyWith(color: C.text3)),
              ),
            for (final s in offered) _seasonCard(year, s),
            if (yr['open'] == true) _yearCard(year, yr),
          ],
        );
      },
    );
  }

  Widget _seasonCard(int year, Map<String, dynamic> s) {
    final k = fmt.d(s['season']).toInt();
    final review = fmt.m(s['review']);
    final cycles = (s['cycles'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [k * 3 - 2, k * 3];
    final status = s['done'] == true ? 'written' : s['onTheDay'] == true ? 'due today' : 'open';
    return Panel(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Season $k review', style: T.title),
          Text('${_cc(cycles.first)} to ${_cc(cycles.last)} · $status', style: T.tiny.copyWith(color: C.text3)),
          const SizedBox(height: 6),
          for (final m in fmt.lm(s['mixes'])) Text(reviewMixLine(fmt.m(m)), style: T.small.copyWith(color: C.text2)),
          const SizedBox(height: 8),
          TextField(key: Key('review-moved-$k'), controller: _c('moved-$k', fmt.s(review['moved'])), minLines: 2, maxLines: 5, maxLength: 1200, decoration: const InputDecoration(labelText: 'What moved')),
          TextField(key: Key('review-change-$k'), controller: _c('change-$k', fmt.s(review['change'])), minLines: 2, maxLines: 5, maxLength: 1200, decoration: const InputDecoration(labelText: 'What to change')),
          const SizedBox(height: 6),
          FilledButton(
            key: Key('review-save-$k'),
            onPressed: () => _post('/api/compass/review/season', {'year': year, 'season': k, 'moved': _c('moved-$k', '').text.trim(), 'change': _c('change-$k', '').text.trim()}, 'Season $k review saved'),
            child: Text(s['done'] == true ? 'Update the review' : 'Save the review'),
          ),
        ],
      ),
    );
  }

  Widget _yearCard(int year, Map<String, dynamic> yr) {
    final review = fmt.m(yr['review']);
    final next = fmt.m(review['nextMix']);
    final firstKey = fmt.s(yr['nextFirstCycle']);
    return Panel(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Year review · Audit', style: T.title),
          Text('the four seasons, side by side', style: T.tiny.copyWith(color: C.text3)),
          const SizedBox(height: 8),
          for (final sr in fmt.lm(yr['seasonReviews']).map(fmt.m))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Season ${fmt.d(sr['season']).toInt()}', style: T.w600(T.small)),
                if (fmt.m(sr['review']).isEmpty)
                  Text('not written', style: T.tiny.copyWith(color: C.text3))
                else ...[
                  Text('Moved: ${fmt.s(fmt.m(sr['review'])['moved'])}', style: T.small),
                  Text('Change: ${fmt.s(fmt.m(sr['review'])['change'])}', style: T.small),
                ],
              ]),
            ),
          TextField(key: const Key('review-summary'), controller: _c('summary', fmt.s(review['summary'])), minLines: 3, maxLines: 6, maxLength: 1200, decoration: const InputDecoration(labelText: 'The year, in your words')),
          const SizedBox(height: 4),
          Text(
            "Next year's first mix (${firstKey.length >= 3 ? firstKey.substring(firstKey.length - 3) : firstKey})${next.isNotEmpty ? ' · set: ${[for (final k in ['primary', 'secondary', 'tertiary']) if (fmt.s(next[k]).isNotEmpty) fmt.s(next[k])].join(' / ')}' : ''}",
            style: T.tiny.copyWith(color: C.text3),
          ),
          TextField(key: const Key('review-next-primary'), controller: _c('np', ''), decoration: const InputDecoration(labelText: 'Primary word')),
          TextField(key: const Key('review-next-secondary'), controller: _c('ns', ''), decoration: const InputDecoration(labelText: 'Secondary (optional)')),
          TextField(key: const Key('review-next-tertiary'), controller: _c('nt', ''), decoration: const InputDecoration(labelText: 'Tertiary (optional)')),
          const SizedBox(height: 6),
          FilledButton(
            key: const Key('review-save-year'),
            onPressed: () {
              final primary = _c('np', '').text.trim();
              final sec = _c('ns', '').text.trim();
              final ter = _c('nt', '').text.trim();
              _post('/api/compass/review/year', {
                'year': year,
                'summary': _c('summary', '').text.trim(),
                if (primary.isNotEmpty) 'nextMix': {'primary': primary, if (sec.isNotEmpty) 'secondary': sec, if (ter.isNotEmpty) 'tertiary': ter},
              }, primary.isNotEmpty ? "Year review saved, next year's first mix set" : 'Year review saved');
            },
            child: Text(review.isNotEmpty ? 'Update the year review' : 'Save the year review'),
          ),
        ],
      ),
    );
  }
}
