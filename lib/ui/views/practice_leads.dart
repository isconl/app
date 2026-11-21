import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Practice > Overview > Leads on the phone (BI26092652): enquiries and booked diagnostics in one time-ordered list, the
/// funnel, a practice filter, and the actions (proposal, won, lost, reply). It reads hub's /api/practice/leads, the same
/// endpoint the console reads. Both stores behind it are still to be built (BS26092502, BS26092604), so the view says which
/// source is connected instead of showing a list that is not real.

/// One line saying which sources are missing, or null when both are connected.
String? leadsSourceNote(Map<String, dynamic> sources) {
  final parts = <String>[];
  for (final (key, label) in [('enquiries', 'Enquiries'), ('bookings', 'Bookings')]) {
    final s = fmt.m(sources[key]);
    final state = fmt.s(s['state']);
    if (state.isEmpty || state == 'ok') continue;
    parts.add(state == 'not-connected'
        ? '$label: not connected yet (${fmt.s(s['pending'])})'
        : '$label: could not be read');
  }
  return parts.isEmpty ? null : '${parts.join(' · ')}. What is connected shows below.';
}

/// "today", "yesterday" or "N days ago" for an ISO time, relative to [now].
String leadAgo(String iso, DateTime now) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = now.toUtc().difference(t.toUtc()).inDays;
  return d <= 0 ? 'today' : d == 1 ? 'yesterday' : '$d days ago';
}

class PracticeLeads extends StatefulWidget {
  const PracticeLeads({super.key});

  @override
  State<PracticeLeads> createState() => _PracticeLeadsState();
}

class _PracticeLeadsState extends State<PracticeLeads> {
  Future<dynamic>? _future;
  String _practice = '';

  Future<dynamic> _fetch() => AppScope.of(context).api.getJson('/api/practice/leads${_practice.isEmpty ? '' : '?practice=${Uri.encodeQueryComponent(_practice)}'}');

  void _reload() {
    final f = _fetch();
    setState(() {
      _future = f;
    });
  }

  Future<void> _act(Map<String, dynamic> lead, String what, {String? status}) async {
    final api = AppScope.of(context).api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = fmt.m(await api.postJson('/api/practice/leads/$what', {'kind': fmt.s(lead['kind']), 'id': fmt.s(lead['id']), 'status': ?status}));
      if (r['ok'] != true) throw ApiException(0, fmt.s(r['error']).isEmpty ? 'refused' : fmt.s(r['error']));
      messenger.showSnackBar(SnackBar(content: Text(what == 'convert' ? 'Proposal drafted in Deck' : 'Marked $status')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not do that')));
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    _future ??= _fetch();
    return FutureBuilder<dynamic>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: MiniSpinner()));
        }
        if (snap.hasError) {
          final e = snap.error;
          return ErrorRetry(e is OfflineException ? 'offline' : e is ApiException ? e.message : 'Could not load leads', onRetry: _reload);
        }
        final d = fmt.m(snap.data);
        if (d['ok'] == false) return EmptyState('Leads', fmt.s(d['error']).isEmpty ? 'Leads could not be read.' : fmt.s(d['error']));
        final leads = fmt.lm(d['leads']).map(fmt.m).toList();
        final practices = d['practices'] is List ? (d['practices'] as List).map(fmt.s).toList() : <String>[];
        final funnel = fmt.m(d['funnel']);
        final total = fmt.m(funnel['total']);
        final note = leadsSourceNote(fmt.m(d['sources']));
        Widget stat(String label, String key) => Expanded(
              child: Column(children: [
                Text('${fmt.d(total[key]).toInt()}', key: Key('funnel-$key'), style: T.title),
                Text(label, style: T.tiny.copyWith(color: C.text3)),
              ]),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Leads', style: T.title),
                  Text('enquiries and booked diagnostics, newest first', style: T.tiny.copyWith(color: C.text3)),
                  if (note != null) ...[
                    const SizedBox(height: 6),
                    Text(note, key: const Key('leads-note'), style: T.tiny.copyWith(color: C.amber)),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [stat('enquiries', 'enquiries'), stat('bookings', 'bookings'), stat('proposals', 'proposals'), stat('won', 'won')]),
                  if (practices.length > 1) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, children: [
                      ChoiceChip(label: const Text('All'), selected: _practice.isEmpty, onSelected: (_) { _practice = ''; _reload(); }),
                      for (final p in practices) ChoiceChip(label: Text(p), selected: _practice == p, onSelected: (_) { _practice = p; _reload(); }),
                    ]),
                  ],
                ],
              ),
            ),
            if (leads.isEmpty)
              const EmptyState('No leads yet', 'They appear here as enquiries arrive and diagnostics are booked.', icon: Icons.person_search_rounded),
            for (final l in leads) _LeadCard(lead: l, onAct: _act),
          ],
        );
      },
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead, required this.onAct});
  final Map<String, dynamic> lead;
  final Future<void> Function(Map<String, dynamic> lead, String what, {String? status}) onAct;

  @override
  Widget build(BuildContext context) {
    final status = fmt.s(lead['status']);
    final closed = status == 'won' || status == 'lost';
    final meta = [
      fmt.s(lead['kind']),
      if (fmt.s(lead['practice']).isNotEmpty) fmt.s(lead['practice']),
      leadAgo(fmt.s(lead['at']), DateTime.now()),
      if (fmt.s(lead['slotAt']).isNotEmpty) 'slot ${fmt.s(lead['slotAt']).substring(0, 16).replaceFirst('T', ' ')}',
    ].where((s) => s.isNotEmpty).join(' · ');
    final id = fmt.s(lead['key']);
    return Panel(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(fmt.s(lead['name']), style: T.body2)),
            Badge2(status, color: status == 'won' ? C.greenBg : status == 'lost' ? C.redBg : C.amberBg,
                textColor: status == 'won' ? C.greenBright : status == 'lost' ? C.red : C.amber),
          ]),
          Text(meta, style: T.tiny.copyWith(color: C.text3)),
          if (fmt.s(lead['summary']).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(fmt.s(lead['summary']), style: T.small),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            if (fmt.s(lead['proposalUrl']).isEmpty)
              FilledButton.tonal(key: Key('convert-$id'), onPressed: () => onAct(lead, 'convert'), child: const Text('Proposal')),
            if (!closed) ...[
              OutlinedButton(key: Key('won-$id'), onPressed: () => onAct(lead, 'mark', status: 'won'), child: const Text('Won')),
              OutlinedButton(key: Key('lost-$id'), onPressed: () => onAct(lead, 'mark', status: 'lost'), child: const Text('Lost')),
            ],
          ]),
        ],
      ),
    );
  }
}
