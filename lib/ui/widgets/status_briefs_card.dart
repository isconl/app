import 'package:flutter/material.dart';

import '../../api/client.dart' show ApiException, OfflineException;
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// BI26100505 (a): the weekly status briefs on the phone, as the console's engagement page has them. Each active subject
/// shows its latest brief (the week, its state, and the Signal, Substance and Trajectory lists), with Draft this week's
/// brief (hub writes it, nothing leaves) and Send by email. A send is outward, so it asks for the address, then shows the
/// recipient and what is being sent and waits for a second tap; a brief already sent offers nothing. Everything needs the
/// live server.

/// The newest brief of a list, by creation date then id, or null.
Map<String, dynamic>? latestBrief(List<Map<String, dynamic>> briefs) {
  if (briefs.isEmpty) return null;
  final sorted = [...briefs]..sort((a, b) {
      final c = fmt.s(b['CREATED_AT']).compareTo(fmt.s(a['CREATED_AT']));
      return c != 0 ? c : fmt.s(b['ID']).compareTo(fmt.s(a['ID']));
    });
  return sorted.first;
}

/// A brief can be sent only while it is a draft.
bool briefSendable(Map<String, dynamic>? brief) => brief != null && fmt.s(brief['STATUS']) == 'draft';

/// A plain check for the recipient: one address with something either side of an @ and a dot after it.
bool looksLikeEmail(String s) {
  final a = s.trim();
  if (a.isEmpty || a.contains(RegExp(r'[\s,;<>"]'))) return false;
  final parts = a.split('@');
  return parts.length == 2 && parts[0].isNotEmpty && parts[1].contains('.') && !parts[1].startsWith('.') && !parts[1].endsWith('.');
}

/// "Engagement Viva" style label for a subject: its source reference, then its type.
String subjectLabel(Map<String, dynamic> s) {
  final ref = fmt.s(s['SOURCE_REF']);
  return ref.isEmpty ? fmt.s(s['SUBJECT_ID']) : ref;
}

class StatusBriefsCard extends StatefulWidget {
  const StatusBriefsCard({super.key});

  @override
  State<StatusBriefsCard> createState() => _StatusBriefsCardState();
}

class _StatusBriefsCardState extends State<StatusBriefsCard> {
  List<({Map<String, dynamic> subject, Map<String, dynamic>? brief})>? _rows;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final subjects = fmt.lm(fmt.m(await api.getJson('/api/active-subjects'))['subjects']).where((s) => fmt.s(s['STATUS']) != 'retired').toList();
      final rows = <({Map<String, dynamic> subject, Map<String, dynamic>? brief})>[];
      for (final s in subjects) {
        final briefs = fmt.lm(fmt.m(await api.getJson('/api/status-briefs?subjectId=${Uri.encodeQueryComponent(fmt.s(s['SUBJECT_ID']))}'))['briefs']);
        rows.add((subject: s, brief: latestBrief(briefs)));
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read the status briefs.');
    }
  }

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

  Future<void> _draft(Map<String, dynamic> subject) async {
    final id = fmt.s(subject['SUBJECT_ID']);
    setState(() => _busy = id);
    final err = await _post('/api/status-briefs/draft', {'subjectId': id});
    if (!mounted) return;
    setState(() => _busy = null);
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    toast(context, 'Brief drafted');
    await _load();
  }

  Future<void> _send(Map<String, dynamic> brief) async {
    final c = TextEditingController();
    final entered = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send by email', style: T.title),
        content: TextField(key: const Key('brief-to'), controller: c, autofocus: true, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'name@example.com')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.body2.copyWith(color: C.text3))),
          FilledButton(key: const Key('brief-to-go'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Next')),
        ],
      ),
    );
    final to = c.text.trim();
    if (entered != true || !mounted) return;
    if (!looksLikeEmail(to)) {
      toast(context, 'Type one email address.', error: true);
      return;
    }
    // The second tap: the recipient and what goes, shown before anything leaves.
    final sure = await confirmDialog(
      context,
      'Send this brief to $to?',
      'The weekly brief for the week of ${fmt.s(brief['WEEK_OF'])} goes out by email now, from you. A sent brief cannot be recalled.',
      action: 'Send',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = fmt.s(brief['ID']));
    final err = await _post('/api/status-briefs/send', {'briefId': fmt.s(brief['ID']), 'via': 'email', 'to': to});
    if (!mounted) return;
    setState(() => _busy = null);
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    toast(context, 'Sent');
    await _load();
  }

  Widget _list(String label, dynamic items) {
    final lines = items is List ? items.map((e) => fmt.s(e)).where((s) => s.isNotEmpty).toList() : <String>[];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: T.label),
        if (lines.isEmpty) Text('none', style: T.small.copyWith(color: C.text3)) else for (final l in lines) Text('- $l', style: T.small.copyWith(color: C.text2)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A short weekly note for each engagement: what is the signal, the substance and the trajectory. Drafting only writes it here; sending is a separate step.', style: T.small.copyWith(color: C.text2)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, key: const Key('briefs-error'), style: T.small.copyWith(color: C.red)),
          ],
          if (rows != null && rows.isEmpty) ...[
            const SizedBox(height: 8),
            Text('No engagements to brief yet.', style: T.small.copyWith(color: C.text3)),
          ],
          for (final r in rows ?? const <({Map<String, dynamic> subject, Map<String, dynamic>? brief})>[])
            Padding(
              key: Key('brief-${fmt.s(r.subject['SUBJECT_ID'])}'),
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(subjectLabel(r.subject), style: T.w500(T.body2))),
                    if (r.brief != null) Badge2('week of ${fmt.s(r.brief!['WEEK_OF'])} · ${fmt.s(r.brief!['STATUS'])}', color: C.surface, textColor: C.text2),
                  ]),
                  if (r.brief == null) Text('No brief drafted yet.', style: T.small.copyWith(color: C.text3)) else ...[
                    _list('Signal', r.brief!['SIGNAL']),
                    _list('Substance', r.brief!['SUBSTANCE']),
                    _list('Trajectory', r.brief!['TRAJECTORY']),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    OutlinedButton(
                      key: Key('brief-draft-${fmt.s(r.subject['SUBJECT_ID'])}'),
                      onPressed: _busy != null ? null : () => _draft(r.subject),
                      child: Text(_busy == fmt.s(r.subject['SUBJECT_ID']) ? 'Drafting...' : 'Draft this week\'s brief'),
                    ),
                    if (briefSendable(r.brief))
                      FilledButton(
                        key: Key('brief-send-${fmt.s(r.brief!['ID'])}'),
                        onPressed: _busy != null ? null : () => _send(r.brief!),
                        child: const Text('Send by email'),
                      ),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
