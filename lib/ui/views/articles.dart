import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Articles Studio, from the phone: what is written, and how far along it is.
///
/// The status is inferred by the server from the filename convention
/// (draft/wip/v0 -> drafting, review/v1 -> review, approved/final -> approved),
/// which is why nothing here is editable. Renaming a file to change its state
/// is a desk action; this view is for knowing where the writing stands.
class ArticlesView extends StatelessWidget {
  const ArticlesView({super.key});

  static Color _statusColor(String status) => switch (status) {
        'drafting' => C.amber,
        'review' => C.cyan,
        'approved' => C.violet,
        'published' => C.greenBright,
        _ => C.text3,
      };

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.articles,
      builder: (context, data) {
        final map = fmt.m(data);
        final articles = fmt.lm(map['articles']);

        if (articles.isEmpty) {
          return const EmptyState(
            'No articles yet',
            'Pieces under Author Nonfiction appear here as you write them.',
            icon: Icons.article_rounded,
          );
        }

        final words =
            articles.fold<int>(0, (sum, a) => sum + fmt.i(a['words']));
        final byStatus = <String, int>{};
        for (final a in articles) {
          final st = fmt.s(a['status']);
          byStatus[st] = (byStatus[st] ?? 0) + 1;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: _stat('PIECES', '${articles.length}', C.greenBright)),
                const SizedBox(width: Sz.gap),
                Expanded(
                    child: _stat('WORDS', fmt.thousands(words), C.cyan)),
                const SizedBox(width: Sz.gap),
                Expanded(
                    child: _stat('IN REVIEW',
                        '${byStatus['review'] ?? 0}', C.violet)),
              ],
            ),
            const SectionLabel('Pieces'),
            ...articles.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ArticleTile(article: a),
                )),
          ],
        );
      },
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.label),
          const SizedBox(height: 4),
          Text(value, style: T.headline.copyWith(color: color, fontSize: 16)),
        ],
      ),
    );
  }
}

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({required this.article});
  final Map<String, dynamic> article;

  @override
  Widget build(BuildContext context) {
    final status = fmt.s(article['status']);
    final color = ArticlesView._statusColor(status);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (status.isNotEmpty)
                Badge2(status,
                    color: color.withValues(alpha: 0.12), textColor: color),
              const Spacer(),
              Text(fmt.shortDate(article['modified']), style: T.monoSmall),
            ],
          ),
          const SizedBox(height: 7),
          Text(fmt.s(article['title']),
              style: T.w600(T.body.copyWith(color: C.text))),
          const SizedBox(height: 5),
          Text(
            [
              fmt.s(article['readingTime']),
              '${fmt.thousands(fmt.i(article['words']))} words',
              fmt.s(article['ext']).replaceFirst('.', ''),
            ].where((v) => v.isNotEmpty).join(' · '),
            style: T.monoSmall,
          ),
        ],
      ),
    );
  }
}
