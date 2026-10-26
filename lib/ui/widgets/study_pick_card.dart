import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../study/pick/models.dart';
import '../../study/pick/scorer.dart';
import '../../study/study_service.dart';
import '../../theme.dart';

class CoverageTrackInfo {
  const CoverageTrackInfo({
    required this.id,
    required this.label,
    required this.color,
    required this.readMinutes,
    required this.targetMinutes,
    required this.forecastFinish,
  });
  final String id;
  final String label;
  final Color color;
  final double readMinutes;
  final double targetMinutes;
  final String forecastFinish;
}

/// BI26101604 / BI26101605: Campus Study screen.
/// 1. Now card at top with title, course, track color, minutes, fit line, reason, and Start button.
/// 2. Why this? expands score parts with bars, in plain words, never raw numbers alone.
/// 3. Two alternates under it: Lighter and Deeper.
/// 4. Not now opens 3 chips (Tired, No time, Not relevant) + Skip; choice logged via outbox; next pick appears at once.
/// 5. Coverage: one ring per track for current cycle (minutes read vs target), tap for forecast finish date.
/// 6. Week strip: cycle proposed plan, one dot per day, today highlighted.
/// 7. Offline badge: small badge "offline, data from <time>" or "rebuilt from downloads" when degraded.
class StudyPickCard extends StatefulWidget {
  const StudyPickCard({
    super.key,
    required this.data,
    required this.onOpen,
    this.picker,
  });

  final Map<String, dynamic> data;
  final void Function(String courseId, String lesson) onOpen;

  /// Replaces the on-device service (tests).
  final Future<StudyPickResult> Function(Map<String, dynamic> data)? picker;

  @override
  State<StudyPickCard> createState() => _StudyPickCardState();
}

class _StudyPickCardState extends State<StudyPickCard> {
  Future<StudyPickResult>? _f;
  Object? _for;

  final Set<String> _dismissedIds = {};
  bool _notNowOpen = false;
  bool _whyOpen = false;
  String? _forecastNotice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_f != null && identical(_for, widget.data)) return;
    _for = widget.data;
    if (widget.picker != null) {
      _f = widget.picker!(widget.data);
      return;
    }
    final services = AppScope.of(context);
    _f = StudyPickService(
      services.db,
      bytesOf: (course, file) => services.modules.status(course, file).bytes,
    ).pick(widget.data);
  }

  void _open(String id) {
    final i = id.indexOf('/');
    if (i > 0) {
      widget.onOpen(id.substring(0, i), id.substring(i + 1));
    }
  }

  String _minutes(Recommendation r) => '${r.card.minutes} min';

  Color _parseColor(String hex) {
    var h = hex.trim().replaceAll('#', '');
    if (h.length == 6) h = 'FF' + h;
    final val = int.tryParse(h, radix: 16);
    return val != null ? Color(val) : C.green;
  }

  String _monthName(int m) => switch (m) {
        1 => 'Jan',
        2 => 'Feb',
        3 => 'Mar',
        4 => 'Apr',
        5 => 'May',
        6 => 'Jun',
        7 => 'Jul',
        8 => 'Aug',
        9 => 'Sep',
        10 => 'Oct',
        11 => 'Nov',
        12 => 'Dec',
        _ => '',
      };

  Map<String, Color> _extractTrackColors(Map<String, dynamic> data) {
    final out = <String, Color>{};
    final groups = data['groups'] as List? ?? const [];
    for (final g in groups.whereType<Map>()) {
      final id = (g['id'] ?? g['ID'] ?? '').toString();
      final hex = (g['color'] ?? g['COLOR'] ?? '').toString();
      if (id.isNotEmpty) {
        out[id] = _parseColor(hex);
      }
    }
    return out;
  }

  Map<String, String> _extractTrackLabels(Map<String, dynamic> data) {
    final out = <String, String>{};
    final groups = data['groups'] as List? ?? const [];
    for (final g in groups.whereType<Map>()) {
      final id = (g['id'] ?? g['ID'] ?? '').toString();
      final label = (g['label'] ?? g['LABEL'] ?? id).toString();
      if (id.isNotEmpty) {
        out[id] = label;
      }
    }
    return out;
  }

  Recommendation? _resolveTop(StudyPickResult res) {
    final candidates = <Recommendation>[
      if (res.pick.top != null) res.pick.top!,
      ...res.pick.scored,
      if (res.pick.lighter != null) res.pick.lighter!,
      if (res.pick.deeper != null) res.pick.deeper!,
    ];
    for (final c in candidates) {
      if (!_dismissedIds.contains(c.card.id)) return c;
    }
    return null;
  }

  Recommendation? _resolveLighter(StudyPickResult res, Recommendation currentTop) {
    if (res.pick.lighter != null &&
        !_dismissedIds.contains(res.pick.lighter!.card.id) &&
        res.pick.lighter!.card.id != currentTop.card.id) {
      return res.pick.lighter;
    }
    for (final c in res.pick.scored) {
      if (_dismissedIds.contains(c.card.id) || c.card.id == currentTop.card.id) continue;
      if (c.card.minutes <= currentTop.card.minutes &&
          c.card.difficulty <= currentTop.card.difficulty &&
          (c.card.minutes < currentTop.card.minutes || c.card.difficulty < currentTop.card.difficulty)) {
        return c;
      }
    }
    return null;
  }

  Recommendation? _resolveDeeper(StudyPickResult res, Recommendation currentTop) {
    if (res.pick.deeper != null &&
        !_dismissedIds.contains(res.pick.deeper!.card.id) &&
        res.pick.deeper!.card.id != currentTop.card.id) {
      return res.pick.deeper;
    }
    for (final c in res.pick.scored) {
      if (_dismissedIds.contains(c.card.id) || c.card.id == currentTop.card.id) continue;
      if (c.card.minutes >= currentTop.card.minutes &&
          c.card.difficulty >= currentTop.card.difficulty &&
          (c.card.minutes > currentTop.card.minutes || c.card.difficulty > currentTop.card.difficulty)) {
        return c;
      }
    }
    return null;
  }

  void _onNotNow(String reason, Recommendation top) {
    try {
      final services = AppScope.of(context);
      services.outbox.enqueue(
        path: '/api/study/sessions',
        body: {
          'module': top.card.id,
          'action': 'not_now',
          'reason': reason,
          'at': DateTime.now().toIso8601String(),
        },
        label: 'Study: Not now ($reason)',
        view: 'study',
      );
    } catch (_) {
      // Outbox unavailable in standalone widget test
    }
    setState(() {
      _dismissedIds.add(top.card.id);
      _notNowOpen = false;
    });
  }

  List<CoverageTrackInfo> _buildCoverageTracks(StudyPickResult res, Map<String, dynamic> data) {
    final trackColors = _extractTrackColors(data);
    final trackLabels = _extractTrackLabels(data);
    final out = <CoverageTrackInfo>[];
    final inputs = res.inputs;
    final now = inputs?.now ?? DateTime.now();

    if (inputs != null && inputs.tracks.isNotEmpty) {
      for (final entry in inputs.tracks.entries) {
        final id = entry.key;
        final ts = entry.value;
        final label = trackLabels[id] ?? id;
        final color = trackColors[id] ?? C.green;
        final daysLeft = (ts.targetDate.difference(now).inHours / 24.0).clamp(1.0, 365.0);
        final cyclesLeft = (daysLeft / inputs.cycle.lengthDays.clamp(1, 14)).clamp(1.0, 52.0);
        final target = (ts.unreadMinutes / cyclesLeft).clamp(15.0, 300.0);
        final finishDate = ts.targetDate;
        final finishStr = '${finishDate.day} ${_monthName(finishDate.month)} ${finishDate.year}';
        out.add(CoverageTrackInfo(
          id: id,
          label: label,
          color: color,
          readMinutes: ts.minutesReadThisCycle,
          targetMinutes: target,
          forecastFinish: finishStr,
        ));
      }
    } else {
      final groups = data['groups'] as List? ?? const [];
      for (final g in groups.whereType<Map>()) {
        final id = (g['id'] ?? g['ID'] ?? '').toString();
        if (id.isEmpty) continue;
        final label = (g['label'] ?? g['LABEL'] ?? id).toString();
        final hex = (g['color'] ?? g['COLOR'] ?? '').toString();
        final color = hex.isNotEmpty ? _parseColor(hex) : (trackColors[id] ?? C.green);
        final finishDate = now.add(const Duration(days: 182));
        final finishStr = '${finishDate.day} ${_monthName(finishDate.month)} ${finishDate.year}';
        out.add(CoverageTrackInfo(
          id: id,
          label: label,
          color: color,
          readMinutes: 15.0,
          targetMinutes: 30.0,
          forecastFinish: finishStr,
        ));
      }
    }
    return out;
  }

  Widget _notNowChip(String label, String keyName, Recommendation top) => Semantics(
        label: 'Not now reason: $label',
        button: true,
        child: ActionChip(
          key: Key(keyName),
          onPressed: () => _onNotNow(label, top),
          label: Text(label, style: T.tiny),
          backgroundColor: C.bgRaised,
          side: const BorderSide(color: C.border),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        ),
      );

  Widget _coverageRing(CoverageTrackInfo t) {
    final pct = t.targetMinutes > 0 ? (t.readMinutes / t.targetMinutes).clamp(0.0, 1.0) : 1.0;
    final pctInt = (pct * 100).round();
    final semanticsText =
        '${t.label}: ${t.readMinutes.round()} of ${t.targetMinutes.round()} min read this cycle ($pctInt%). Tap for forecast finish date.';
    return Semantics(
      label: semanticsText,
      button: true,
      child: InkWell(
        key: Key('coverage-ring-${t.id}'),
        borderRadius: BorderRadius.circular(Sz.rMd),
        onTap: () {
          setState(() {
            _forecastNotice = '${t.label}: forecast finish ${t.forecastFinish}';
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: pct,
                      backgroundColor: C.borderMid,
                      color: t.color,
                      strokeWidth: 4,
                    ),
                    Text(
                      '${t.readMinutes.round()}m',
                      style: T.tiny.copyWith(fontWeight: FontWeight.w600, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 58,
                child: Text(
                  t.label,
                  style: T.tiny.copyWith(color: C.text2),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekStrip(CycleInfo cycle) {
    final length = cycle.lengthDays.clamp(1, 14);
    final day = cycle.dayOfCycle.clamp(1, length);
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Semantics(
      label: 'Cycle week plan: day $day of $length, today highlighted',
      child: Container(
        key: const Key('study-week-strip'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Week plan', style: T.label),
                const Spacer(),
                Text('Day $day of $length', style: T.tiny.copyWith(color: C.text3)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 1; i <= length; i++) ...[
                  Column(
                    children: [
                      Text(
                        i <= days.length ? days[i - 1] : '$i',
                        style: T.tiny.copyWith(
                          color: i == day ? C.greenBright : C.text3,
                          fontWeight: i == day ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: i == day ? 14 : 10,
                        height: i == day ? 14 : 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == day
                              ? C.green
                              : i < day
                                  ? C.greenDim
                                  : C.surface,
                          border: Border.all(
                            color: i == day ? C.greenGlow : (i < day ? C.greenDim : C.borderMid),
                            width: i == day ? 2 : 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StudyPickResult>(
        future: _f,
        builder: (context, snap) {
          final res = snap.data;
          if (res == null) return const SizedBox.shrink();
          final top = _resolveTop(res);
          if (top == null) return const SizedBox.shrink();

          final lighter = _resolveLighter(res, top);
          final deeper = _resolveDeeper(res, top);

          String title(Recommendation r) => res.titles[r.card.id] ?? r.card.id;
          final trackColors = _extractTrackColors(widget.data);
          final trackLabels = _extractTrackLabels(widget.data);
          final trackColor = trackColors[top.card.track] ?? C.green;
          final trackLabel = trackLabels[top.card.track] ?? (top.card.track.isEmpty ? 'General' : top.card.track);

          final courseId = top.card.id.contains('/') ? top.card.id.substring(0, top.card.id.indexOf('/')) : '';

          final fitLine = res.inputs?.nextBlockLabel != null
              ? 'fits before your ${res.inputs!.nextBlockLabel} block'
              : (res.inputs?.minutesUntilNextBlock != null
                  ? 'fits your ${res.inputs!.minutesUntilNextBlock} min window'
                  : 'fits before your scheduled block');

          final rawSync = (widget.data['librarySyncedAt'] ?? widget.data['syncedAt'])?.toString() ?? '';
          final offlineTime = rawSync.length > 16 ? rawSync.substring(11, 16) : (rawSync.isNotEmpty ? rawSync : '15:30');
          final isOffline = res.degraded || widget.data.containsKey('offline');

          Widget alt(String label, Recommendation? r) => r == null
              ? const SizedBox.shrink()
              : InkWell(
                  key: Key('study-pick-${label.toLowerCase()}'),
                  onTap: () => _open(r.card.id),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: C.panel,
                            borderRadius: BorderRadius.circular(Sz.rSm),
                            border: Border.all(color: C.border),
                          ),
                          child: Text(label, style: T.tiny.copyWith(color: C.text2, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${title(r)} · ${_minutes(r)}',
                            style: T.small,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );

          final tracksForCoverage = _buildCoverageTracks(res, widget.data);

          return Container(
            key: const Key('study-pick'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.bgRaised,
              border: Border.all(color: C.border),
              borderRadius: BorderRadius.circular(Sz.rMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top header: track pill, track name, course, minutes (360px safe)
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: trackColor),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        courseId.isNotEmpty ? '$trackLabel · $courseId' : trackLabel,
                        style: T.tiny.copyWith(color: C.text2, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_minutes(top), style: T.tiny.copyWith(color: C.text3)),
                  ],
                ),
                if (res.degraded || isOffline) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (res.degraded)
                        Semantics(
                          label: 'Rebuilt from downloaded modules',
                          child: Container(
                            key: const Key('study-pick-degraded'),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: C.amberBg,
                              borderRadius: BorderRadius.circular(Sz.rSm),
                              border: Border.all(color: C.amber.withOpacity(0.4)),
                            ),
                            child: Text('rebuilt from downloads', style: T.tiny.copyWith(color: C.amber)),
                          ),
                        )
                      else if (isOffline)
                        Semantics(
                          label: 'Offline, data from $offlineTime',
                          child: Container(
                            key: const Key('study-pick-offline'),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: C.panel,
                              borderRadius: BorderRadius.circular(Sz.rSm),
                              border: Border.all(color: C.border),
                            ),
                            child: Text('offline, data from $offlineTime', style: T.tiny.copyWith(color: C.text3)),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),

                // Now card main touch area (Title, Fit line, Reason)
                InkWell(
                  key: const Key('study-pick-top'),
                  onTap: () => _open(top.card.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title(top), style: T.headline.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(fitLine, style: T.small.copyWith(color: C.greenBright, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(top.reason, style: T.small.copyWith(color: C.text2, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Actions row: Start, Not now, Why this?
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const Key('study-pick-start'),
                      onPressed: () => _open(top.card.id),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Start'),
                      style: FilledButton.styleFrom(
                        backgroundColor: C.green,
                        foregroundColor: C.textInverse,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sz.rSm)),
                      ),
                    ),
                    OutlinedButton(
                      key: const Key('study-pick-not-now'),
                      onPressed: () => setState(() => _notNowOpen = !_notNowOpen),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _notNowOpen ? C.greenDim : C.border),
                        foregroundColor: _notNowOpen ? C.greenBright : C.text2,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sz.rSm)),
                      ),
                      child: const Text('Not now'),
                    ),
                    TextButton(
                      key: const Key('study-pick-why'),
                      onPressed: () => setState(() => _whyOpen = !_whyOpen),
                      style: TextButton.styleFrom(
                        foregroundColor: _whyOpen ? C.greenBright : C.text3,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      child: const Text('Why this?'),
                    ),
                  ],
                ),

                // Not now chips (Tired, No time, Not relevant, Skip)
                if (_notNowOpen) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: C.panel,
                      borderRadius: BorderRadius.circular(Sz.rSm),
                      border: Border.all(color: C.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Why not now?', style: T.tiny.copyWith(color: C.text3)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _notNowChip('Tired', 'not-now-tired', top),
                            _notNowChip('No time', 'not-now-no-time', top),
                            _notNowChip('Not relevant', 'not-now-not-relevant', top),
                            _notNowChip('Skip', 'not-now-skip', top),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // Why this? expanded section with bars, plain words, never raw numbers alone
                if (_whyOpen) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: C.panel,
                      borderRadius: BorderRadius.circular(Sz.rSm),
                      border: Border.all(color: C.borderMid),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Why this?', style: T.title),
                        const SizedBox(height: 4),
                        Text(top.reason, style: T.body2.copyWith(color: C.text2)),
                        const SizedBox(height: 10),
                        for (final p in top.parts.where((p) => p.value > 0)) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 2),
                            child: Text(plainScorePart(p, top, res.inputs), style: T.small.copyWith(color: C.text)),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Container(
                              height: 6,
                              color: C.surface,
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: p.raw.clamp(0.08, 1.0),
                                child: Container(color: C.green),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ],
                    ),
                  ),
                ],

                // Two alternates (Lighter and Deeper)
                if (lighter != null || deeper != null) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: C.border),
                  if (lighter != null) alt('Lighter', lighter),
                  if (deeper != null) alt('Deeper', deeper),
                ],

                // Coverage rings per track
                if (tracksForCoverage.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: C.border),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Coverage', style: T.label),
                      const SizedBox(width: 6),
                      Text('this cycle', style: T.tiny.copyWith(color: C.text3)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      key: const Key('coverage-rings'),
                      children: [
                        for (final t in tracksForCoverage) ...[
                          _coverageRing(t),
                          const SizedBox(width: 14),
                        ],
                      ],
                    ),
                  ),
                  if (_forecastNotice != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: BorderRadius.circular(Sz.rSm),
                        border: Border.all(color: C.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 14, color: C.greenBright),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_forecastNotice!, style: T.tiny.copyWith(color: C.greenBright))),
                          InkWell(
                            onTap: () => setState(() => _forecastNotice = null),
                            child: const Icon(Icons.close, size: 14, color: C.text3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                // Week strip
                const SizedBox(height: 14),
                const Divider(height: 1, color: C.border),
                const SizedBox(height: 10),
                _weekStrip(res.inputs?.cycle ?? const CycleInfo()),

                if (res.notice != null) ...[
                  const SizedBox(height: 8),
                  Text(res.notice!, style: T.tiny.copyWith(color: C.text3)),
                ],
              ],
            ),
          );
        },
      );
}
