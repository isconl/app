import 'dart:async';

import 'package:flutter/material.dart';

import 'client.dart';
import 'models.dart';
import 'tokens.dart';

/// Sessions grouped by machine. Pull to refresh, and a refresh every 30
/// seconds on its own.
class SessionsBoard extends StatefulWidget {
  const SessionsBoard({
    super.key,
    required this.client,
    this.now = DateTime.now,
    this.refreshEvery = const Duration(seconds: 30),
  });

  final SlateClient client;
  final DateTime Function() now;
  final Duration refreshEvery;

  @override
  State<SessionsBoard> createState() => _SessionsBoardState();
}

class _SessionsBoardState extends State<SessionsBoard> {
  List<SessionInfo>? _sessions;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(widget.refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.client.sessions();
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    final sessions = _sessions;
    if (sessions == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Text('Could not reach slate.', style: TextStyle(color: t.danger)),
      );
    }
    final byMachine = <String, List<SessionInfo>>{};
    for (final s in sessions) {
      byMachine.putIfAbsent(s.machine, () => []).add(s);
    }
    final machines = byMachine.keys.toList()..sort();
    final now = widget.now();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Showing the last good read; slate did not answer.',
                  style: TextStyle(color: t.warn, fontSize: 12)),
            ),
          if (sessions.isEmpty)
            Text('No sessions have checked in.', style: TextStyle(color: t.text2)),
          for (final m in machines) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(m.toUpperCase(),
                  style: TextStyle(
                      color: t.text3,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
            ),
            for (final s in byMachine[m]!) SessionCard(session: s, now: now),
          ],
        ],
      ),
    );
  }
}

class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.session, required this.now});

  final SessionInfo session;
  final DateTime now;

  static String ageText(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    final s = session;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(s.id,
                  style: TextStyle(
                      color: t.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'JetBrains Mono')),
            ),
            if (s.isIdle(now)) _Badge(text: 'idle', color: t.danger),
            if (s.isStalled(now)) _Badge(text: 'stalled', color: t.warn),
          ]),
          const SizedBox(height: 6),
          Text(
            [s.kind, if (s.model != null) s.model!].join(' · '),
            style: TextStyle(color: t.text2, fontSize: 12),
          ),
          if (s.currentRowTitle != null || s.currentRow != null) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (s.progress != null) s.progress!,
                if (s.currentRow != null) s.currentRow!,
                if (s.currentRowTitle != null) s.currentRowTitle!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.text, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          Text('checked in ${ageText(s.age(now))}',
              style: TextStyle(color: t.text3, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 10.5)),
      );
}
