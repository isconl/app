import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme.dart';
import 'dashboard.dart';

/// Debug-only review screen: every dashboard widget with fixture data,
/// including the empty and error states.
class DashboardGallery extends StatelessWidget {
  const DashboardGallery({super.key});

  /// Opens the gallery; does nothing outside debug builds.
  static void open(BuildContext context) {
    if (!kDebugMode) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DashboardGallery()));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(title: const Text('Dashboard kit')),
      body: ListView(
        padding: const EdgeInsets.all(Sz.pad),
        children: [
          DashboardGrid(
            items: [
              DashItem(
                StatTile(
                  label: 'Unread',
                  value: '42',
                  delta: -6,
                  deltaGoodWhenUp: false,
                  trend: const [9, 7, 8, 5, 6, 4, 3],
                  onTap: () {},
                  updatedAt: now.subtract(const Duration(minutes: 4)),
                ),
              ),
              const DashItem(
                StatTile(
                  label: 'Response time',
                  value: '1.4',
                  unit: 'h',
                  delta: 0.3,
                  deltaGoodWhenUp: false,
                ),
              ),
              const DashItem(StatTile(label: 'Empty', value: null)),
              const DashItem(
                StatTile(label: 'Stale', value: '7', error: 'offline'),
              ),
              DashItem(
                DashTile(
                  label: 'Day blocks',
                  child: Row(
                    children: const [
                      RingGauge(
                        arcs: [
                          RingArc(5, C.green),
                          RingArc(2, C.amber),
                          RingArc(1, C.cyan),
                        ],
                        total: 12,
                        center: '8/12',
                        caption: 'blocks',
                      ),
                    ],
                  ),
                ),
              ),
              DashItem(
                DashTile(
                  label: 'Kanban',
                  child: BarStrip(
                    segments: const [
                      BarSegment('To do', 6, C.amber),
                      BarSegment('Doing', 3, C.cyan),
                      BarSegment('Done', 11, C.green),
                    ],
                  ),
                ),
              ),
              DashItem(
                DashTile(
                  label: 'Unread by source, 7 days',
                  child: StackedBars(
                    series: const [
                      BarSeries('Mail', C.cyan),
                      BarSeries('Teams', C.violet),
                      BarSeries('Other', C.amber),
                    ],
                    days: const [
                      [3, 1, 0],
                      [4, 2, 1],
                      [2, 2, 0],
                      [5, 1, 1],
                      [3, 0, 2],
                      [1, 1, 0],
                      [2, 3, 1],
                    ],
                    dayLabels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                  ),
                ),
                span: 2,
              ),
              DashItem(
                DashTile(
                  label: 'Due next',
                  child: MiniList(
                    items: const [
                      MiniItem('Reply to Joel', 'today'),
                      MiniItem('Review PR', 'tomorrow'),
                      MiniItem('Invoice', 'Fri'),
                      MiniItem('Hidden fourth', 'Sat'),
                    ],
                  ),
                ),
                span: 2,
              ),
              const DashItem(
                DashTile(
                  label: 'Empty chart',
                  child: StackedBars(series: [], days: []),
                ),
                span: 2,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
