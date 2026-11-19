import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// Computed data-quality checks, shown only when something needs attention -
/// ported from dashboard/app.js's fetchDataHealth() (~line 753), which reads
/// the same /api/health/data shape this already-registered snapshot
/// (Store.dataHealth) has never had a consumer for until now.
class DataHealthCard extends StatefulWidget {
  const DataHealthCard({super.key});

  @override
  State<DataHealthCard> createState() => _DataHealthCardState();
}

class _DataHealthCardState extends State<DataHealthCard> {
  @override
  void initState() {
    super.initState();
    // No consumer existed before this widget, so nothing has ever hydrated
    // or refreshed this snapshot - unlike SnapshotView-backed views, which
    // inherit that from the store already having a reader.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      services.store.dataHealth.hydrate().then((_) {
        if (mounted) services.store.dataHealth.refresh();
      });
    });
  }

  static const _severityIcon = {
    'critical': '●',
    'warn': '●',
    'info': '○',
  };
  static const _severityColor = {
    'critical': C.red,
    'warn': C.amber,
    'info': C.text3,
  };

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.dataHealth,
      builder: (context, _) {
        final issues = fmt.lm(fmt.m(services.store.dataHealth.value)['issues']);
        if (issues.isEmpty) return const SizedBox.shrink();
        return Panel(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Data health', style: T.w600(T.body2.copyWith(color: C.text))),
                  const Spacer(),
                  Text(
                      '${issues.length} item${issues.length > 1 ? 's' : ''} '
                      'need${issues.length > 1 ? '' : 's'} attention',
                      style: T.monoSmall),
                ],
              ),
              const SizedBox(height: 8),
              for (final i in issues)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _severityIcon[fmt.s(i['severity'])] ?? '○',
                          style: T.small.copyWith(
                              color: _severityColor[fmt.s(i['severity'])] ??
                                  C.text3)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(fmt.s(i['text']), style: T.small)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
