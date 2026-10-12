import 'package:flutter/material.dart';

import '../../api/client.dart' show ApiException, OfflineException;
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100511: Settings > News watch. The console's two lists and its sweep, on the phone: the competitors the news
/// sweep watches for, the freeform terms (locations and topics), and a Run sweep button. Everything goes through hub's
/// `/api/news/*` routes and needs the live server. The sweep costs search and AI budget, so it blocks a second tap while
/// it runs. The sweep answers with a count of new matches, which are raised as alerts; the card says that and does not
/// present the count as news.

/// A row is on unless it says "disabled".
bool newsActive(Map<String, dynamic> row) => fmt.s(row['STATUS']).isEmpty || fmt.s(row['STATUS']) == 'active';

/// "venture / competitor", or just the competitor when no venture is set (the server stores "-" for empty).
String competitorLine(Map<String, dynamic> c) {
  final v = fmt.s(c['VENTURE']);
  final name = fmt.s(c['COMPETITOR']);
  return v.isEmpty || v == '-' ? name : '$v / $name';
}

/// The sentence under the sweep button for a finished sweep.
String sweepResultLine(Map<String, dynamic> r) {
  final n = r['raised'] is num ? (r['raised'] as num).toInt() : 0;
  return n == 0 ? 'Sweep finished. Nothing new.' : 'Sweep finished. $n new match${n == 1 ? '' : 'es'} raised as alert${n == 1 ? '' : 's'}.';
}

class NewsWatchCard extends StatefulWidget {
  const NewsWatchCard({super.key});

  @override
  State<NewsWatchCard> createState() => _NewsWatchCardState();
}

class _NewsWatchCardState extends State<NewsWatchCard> {
  List<Map<String, dynamic>>? _competitors;
  List<Map<String, dynamic>>? _topics;
  bool _sweeping = false;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final c = fmt.m(await api.getJson('/api/news/competitors'));
      final t = fmt.m(await api.getJson('/api/news/topics'));
      if (!mounted) return;
      setState(() {
        _competitors = fmt.lm(c['competitors']);
        _topics = fmt.lm(t['topics']);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read what is being watched.');
    }
  }

  /// One write through hub. Returns null on success, otherwise a sentence.
  Future<String?> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = fmt.m(await AppScope.of(context).mutations.post(path, body));
      if (r['success'] == false) return fmt.s(r['error']).isEmpty ? 'That did not work.' : fmt.s(r['error']);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on OfflineException {
      return 'This needs the live server - you are offline.';
    }
  }

  Future<void> _afterWrite(String? err, String done) async {
    if (!mounted) return;
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    toast(context, done);
    await _load();
  }

  Future<void> _addCompetitor() async {
    final venture = TextEditingController();
    final name = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Watch a competitor', style: T.title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('news-comp-name'), controller: name, autofocus: true, maxLength: 120, decoration: const InputDecoration(hintText: 'Competitor name')),
          TextField(key: const Key('news-comp-venture'), controller: venture, maxLength: 60, decoration: const InputDecoration(hintText: 'Which of your ventures it competes with (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
          FilledButton(key: const Key('news-comp-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (go != true || name.text.trim().isEmpty || !mounted) return;
    final err = await _post('/api/news/competitors', {'venture': venture.text.trim(), 'competitor': name.text.trim(), 'status': 'active'});
    await _afterWrite(err, '${name.text.trim()} added');
  }

  Future<void> _addTopic() async {
    final term = TextEditingController();
    var kind = 'topic';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Watch a term', style: T.title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('news-topic-term'), controller: term, autofocus: true, maxLength: 120, decoration: const InputDecoration(hintText: 'A location or a topic')),
            Segmented(options: const ['topic', 'location'], value: kind, onChanged: (v) => setD(() => kind = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
            FilledButton(key: const Key('news-topic-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (go != true || term.text.trim().isEmpty || !mounted) return;
    final err = await _post('/api/news/topics', {'kind': kind, 'term': term.text.trim(), 'status': 'active'});
    await _afterWrite(err, '${term.text.trim()} added');
  }

  Future<void> _setActive(String path, Map<String, dynamic> row, Map<String, dynamic> fields, bool on) async {
    final err = await _post(path, {'id': fmt.s(row['ID']), ...fields, 'status': on ? 'active' : 'disabled'});
    await _afterWrite(err, on ? 'Watching again' : 'Paused');
  }

  Future<void> _delete(String path, Map<String, dynamic> row, String what) async {
    final sure = await confirmDialog(context, 'Stop watching $what?', 'It is removed from the list and the sweep no longer looks for it.', action: 'Remove', destructive: true);
    if (!sure || !mounted) return;
    final err = await _post(path, {'id': fmt.s(row['ID'])});
    await _afterWrite(err, 'Removed');
  }

  Future<void> _sweep() async {
    if (_sweeping) return;
    setState(() {
      _sweeping = true;
      _result = null;
    });
    String line;
    try {
      final r = fmt.m(await AppScope.of(context).mutations.post('/api/news/sweep', {}));
      line = r['success'] == false ? (fmt.s(r['error']).isEmpty ? 'The sweep failed.' : fmt.s(r['error'])) : sweepResultLine(r);
    } on ApiException catch (e) {
      line = e.message;
    } on OfflineException {
      line = 'A sweep needs the live server - you are offline.';
    }
    if (!mounted) return;
    setState(() {
      _sweeping = false;
      _result = line;
    });
  }

  Widget _row({required Key key, required String title, required String? sub, required bool on, required ValueChanged<bool> onToggle, required VoidCallback onDelete}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        key: key,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.body2.copyWith(color: on ? C.text : C.text3)),
              if (sub != null) Text(sub, style: T.monoSmall),
            ]),
          ),
          Switch(value: on, onChanged: onToggle),
          IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline_rounded, size: 18, color: C.text3), onPressed: onDelete),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final comps = _competitors;
    final topics = _topics;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The news sweep looks for every active line below and raises an alert for each new match. A topic is any term to watch: '
            'a place, an industry, a person. A competitor is a rival to one of your ventures.',
            style: T.small.copyWith(color: C.text2),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, key: const Key('news-error'), style: T.small.copyWith(color: C.red)),
          ],
          const SizedBox(height: 10),
          Text('COMPETITORS', style: T.label),
          if (comps != null && comps.isEmpty) Text('None yet.', style: T.small.copyWith(color: C.text3)),
          for (final c in comps ?? const <Map<String, dynamic>>[])
            _row(
              key: Key('news-comp-${fmt.s(c['ID'])}'),
              title: competitorLine(c),
              sub: null,
              on: newsActive(c),
              onToggle: (v) => _setActive('/api/news/competitors', c, {'venture': fmt.s(c['VENTURE']) == '-' ? '' : fmt.s(c['VENTURE']), 'competitor': fmt.s(c['COMPETITOR'])}, v),
              onDelete: () => _delete('/api/news/competitors/delete', c, fmt.s(c['COMPETITOR'])),
            ),
          TextButton(key: const Key('news-add-comp'), onPressed: _addCompetitor, child: const Text('Add a competitor')),
          const SizedBox(height: 6),
          Text('TERMS', style: T.label),
          if (topics != null && topics.isEmpty) Text('None yet.', style: T.small.copyWith(color: C.text3)),
          for (final t in topics ?? const <Map<String, dynamic>>[])
            _row(
              key: Key('news-topic-${fmt.s(t['ID'])}'),
              title: fmt.s(t['TERM']),
              sub: fmt.s(t['KIND']).isEmpty ? null : fmt.s(t['KIND']),
              on: newsActive(t),
              onToggle: (v) => _setActive('/api/news/topics', t, {'kind': fmt.s(t['KIND']).isEmpty ? 'topic' : fmt.s(t['KIND']), 'term': fmt.s(t['TERM'])}, v),
              onDelete: () => _delete('/api/news/topics/delete', t, fmt.s(t['TERM'])),
            ),
          TextButton(key: const Key('news-add-topic'), onPressed: _addTopic, child: const Text('Add a term')),
          const Divider(),
          OutlinedButton(
            key: const Key('news-sweep'),
            onPressed: _sweeping ? null : _sweep,
            child: Text(_sweeping ? 'Sweeping...' : 'Run sweep now'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            Text(_result!, key: const Key('news-result'), style: T.small.copyWith(color: C.text2)),
          ],
        ],
      ),
    );
  }
}
