import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/db.dart' show ReadingAnchor;
import '../../theme.dart';
import '../widgets/common.dart';
import 'learning.dart' show LessonScreen;

/// BI26100325: the Today card that resumes the most recent unfinished module at
/// the block where it was left. Shows nothing when there is none.
class ContinueReadingCard extends StatefulWidget {
  const ContinueReadingCard({super.key});

  @override
  State<ContinueReadingCard> createState() => _ContinueReadingCardState();
}

class _ContinueReadingCardState extends State<ContinueReadingCard> {
  ReadingAnchor? _anchor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final a = await AppScope.of(context).db.latestUnfinishedReading();
    if (mounted) setState(() => _anchor = a);
  }

  @override
  Widget build(BuildContext context) {
    final a = _anchor;
    if (a == null) return const SizedBox.shrink();
    final left = a.minutesLeft;
    final where = [
      a.course,
      if (a.movement.isNotEmpty) a.movement,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        key: const Key('continue-reading-card'),
        onTap: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => LessonScreen(
                course: a.course,
                file: a.file,
                title: a.title,
                status: 'learning',
              ),
            ),
          );
          _load();
        },
        child: Row(
          children: [
            const Icon(Icons.menu_book_rounded, size: 20, color: C.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Continue reading', style: T.label.copyWith(color: C.green)),
                  const SizedBox(height: 2),
                  Text(a.title.isEmpty ? a.file : a.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: T.body.copyWith(color: C.text)),
                  const SizedBox(height: 2),
                  Text(
                    left > 0 ? '$where · about $left min left' : where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.small.copyWith(color: C.text3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: C.text3),
          ],
        ),
      ),
    );
  }
}
