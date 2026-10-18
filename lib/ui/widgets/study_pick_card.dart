import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../study/pick/scorer.dart';
import '../../study/study_service.dart';
import '../../theme.dart';

/// BI26101604: "Study next", the on-phone pick. It reads only what is on the device (the `learning` snapshot and local
/// progress), so it opens on a pick with its reason in airplane mode. When the study index cache is missing or damaged
/// the pick says so quietly and uses the modules already downloaded.
class StudyPickCard extends StatefulWidget {
  const StudyPickCard({super.key, required this.data, required this.onOpen, this.picker});
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
    _f = StudyPickService(services.db, bytesOf: (course, file) => services.modules.status(course, file).bytes).pick(widget.data);
  }

  void _open(String id) {
    final i = id.indexOf('/');
    if (i > 0) widget.onOpen(id.substring(0, i), id.substring(i + 1));
  }

  String _minutes(Recommendation r) => '${r.card.minutes} min';

  void _why(BuildContext context, StudyPickResult res) {
    final r = res.pick.top!;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Why this?', style: T.title),
            const SizedBox(height: 6),
            Text(r.reason, style: T.body2),
            const SizedBox(height: 10),
            for (final p in r.parts.where((p) => p.value > 0))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text(p.name, style: T.small)),
                  Text(p.value.toStringAsFixed(2), style: T.monoSmall),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StudyPickResult>(
        future: _f,
        builder: (context, snap) {
          final res = snap.data;
          final top = res?.pick.top;
          if (res == null || top == null) return const SizedBox.shrink();
          String title(Recommendation r) => res.titles[r.card.id] ?? r.card.id;
          Widget alt(String label, Recommendation? r) => r == null
              ? const SizedBox.shrink()
              : InkWell(
                  key: Key('study-pick-${label.toLowerCase()}'),
                  onTap: () => _open(r.card.id),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('$label: ${title(r)} · ${_minutes(r)}', style: T.small),
                  ),
                );
          return Container(
            key: const Key('study-pick'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Study next', style: T.label),
              const SizedBox(height: 6),
              InkWell(
                key: const Key('study-pick-top'),
                onTap: () => _open(top.card.id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title(top), style: T.title),
                  Text(_minutes(top), style: T.tiny),
                  const SizedBox(height: 4),
                  Text(top.reason, style: T.small.copyWith(fontStyle: FontStyle.italic)),
                ]),
              ),
              alt('Lighter', res.pick.lighter),
              alt('Deeper', res.pick.deeper),
              Row(children: [
                TextButton(key: const Key('study-pick-why'), onPressed: () => _why(context, res), child: const Text('Why this?')),
                const Spacer(),
                if (res.degraded) Text('from downloaded modules', key: const Key('study-pick-degraded'), style: T.tiny.copyWith(color: C.amber)),
              ]),
              if (res.notice != null) Text(res.notice!, style: T.tiny),
            ]),
          );
        },
      );
}
