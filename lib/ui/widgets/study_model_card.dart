import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../study/session_log.dart';
import '../../theme.dart';
import 'common.dart';

class StudyModelSettingCard extends StatefulWidget {
  const StudyModelSettingCard({super.key});

  @override
  State<StudyModelSettingCard> createState() => _StudyModelSettingCardState();
}

class _StudyModelSettingCardState extends State<StudyModelSettingCard> {
  int _sessionCount = 0;
  bool _nudgesEnabled = true;
  bool _weekendNudges = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final db = AppScope.of(context).db;
      final count = await db.getStudySessionCount();
      if (mounted) setState(() => _sessionCount = count);
    } catch (_) {}
  }

  Future<void> _seed() async {
    try {
      final services = AppScope.of(context);
      final log = StudySessionLog(services.db, outbox: services.outbox);
      await log.seedTestSessions(30);
      await _refresh();
    } catch (e) {
      debugPrint('Seed error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _sessionCount >= 30;
    final statusText = isActive
        ? 'Active (trained on $_sessionCount sessions)'
        : 'Off (waiting for 30 sessions, currently $_sessionCount/30)';

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Study finish model', style: T.label),
                    const SizedBox(height: 4),
                    Text(
                      statusText,
                      key: const Key('study-finish-model-status'),
                      style: T.small.copyWith(color: isActive ? C.greenBright : C.amber),
                    ),
                  ],
                ),
              ),
              if (!isActive)
                TextButton(
                  key: const Key('seed-study-sessions'),
                  onPressed: _seed,
                  child: const Text('Seed 30'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: C.border),
          const SizedBox(height: 8),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const Key('study-nudge-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text('Proactive study nudges', style: T.label),
              subtitle: Text('One nudge a day before free blocks; off weekends by default', style: T.tiny.copyWith(color: C.text3)),
              value: _nudgesEnabled,
              onChanged: (v) => setState(() => _nudgesEnabled = v),
            ),
          ),
        ],
      ),
    );
  }
}
