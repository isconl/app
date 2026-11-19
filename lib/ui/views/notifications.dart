import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Ranked notice board. Server-side RANK ordering is preserved.
class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  bool _newOnly = true;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.notifications,
      builder: (context, data) {
        final map = fmt.m(data);
        final all = fmt.lm(map['notifications']);
        final items = _newOnly
            ? all
                .where((n) => fmt.s(n['STATUS']).toLowerCase() == 'new')
                .toList()
            : all;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Pill('New',
                    selected: _newOnly,
                    onTap: () => setState(() => _newOnly = true)),
                const SizedBox(width: 6),
                Pill('All',
                    selected: !_newOnly,
                    onTap: () => setState(() => _newOnly = false)),
                const Spacer(),
                if (items.isNotEmpty && _newOnly)
                  TextButton(
                    onPressed: () async {
                      final res =
                          await services.mutations.markSeen(all: true);
                      if (!context.mounted) return;
                      if (!res.ok) toast(context, res.error!, error: true);
                    },
                    child: const Text('Mark all seen'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              EmptyState(
                _newOnly ? 'Nothing needs you' : 'No notices',
                _newOnly
                    ? 'The agent raises alerts here when something needs '
                        'attention - overdue work, late income, sync failures.'
                    : 'Notices will accumulate as the agent watches your world.',
                icon: Icons.notifications_none_rounded,
              )
            else
              ...items.map((n) => _NoticeTile(
                    notice: n,
                    onSeen: () async {
                      final res = await services.mutations
                          .markSeen(ids: [fmt.s(n['ID'])]);
                      if (!context.mounted) return;
                      if (!res.ok) toast(context, res.error!, error: true);
                    },
                  )),
          ],
        );
      },
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.notice, required this.onSeen});
  final Map<String, dynamic> notice;
  final Future<void> Function() onSeen;

  @override
  Widget build(BuildContext context) {
    final severity = fmt.s(notice['SEVERITY']);
    final isNew = fmt.s(notice['STATUS']).toLowerCase() == 'new';
    final color = C.forSeverity(severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: EdgeInsets.zero,
        onTap: isNew ? onSeen : null,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: isNew ? color : C.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Badge2(fmt.s(notice['SOURCE']),
                              color: C.surface, textColor: C.text3),
                          const SizedBox(width: 6),
                          if (fmt.s(notice['KIND']).isNotEmpty)
                            Badge2(fmt.s(notice['KIND']),
                                color: severity == 'high'
                                    ? C.redBg
                                    : C.surface,
                                textColor: severity == 'high'
                                    ? C.red
                                    : C.text3),
                          const Spacer(),
                          Text(fmt.ago(notice['TS']), style: T.monoSmall),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(fmt.s(notice['TITLE']),
                          style: isNew
                              ? T.w600(T.body2)
                              : T.body2.copyWith(color: C.text2)),
                      if (fmt.s(notice['BODY']).isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(fmt.s(notice['BODY']),
                            style: T.small.copyWith(color: C.text3),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ],
                      if (isNew)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('tap to mark seen',
                              style: T.monoSmall.copyWith(fontSize: 9)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
