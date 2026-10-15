import 'package:flutter/material.dart';

import 'client.dart';
import 'loader.dart';
import 'rows_models.dart';
import 'sessions_board.dart';
import 'tokens.dart';

/// Blockers raised by sessions, oldest first. Clearing needs evidence and step-up.
class BlockersView extends StatelessWidget {
  const BlockersView({super.key, required this.client, required this.stepUp, this.now = DateTime.now});
  final SlateClient client;
  final WriteStepUp stepUp;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => Loader<List<BlockerInfo>>(
        load: client.blockers,
        builder: (context, list, reload) {
          final t = SlateTokens.of(context);
          final sorted = [...list]..sort((a, b) => a.raisedAt.compareTo(b.raisedAt));
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text('${sorted.length} open', style: TextStyle(color: t.text2, fontSize: 12)),
                const SizedBox(height: 8),
                for (final b in sorted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.hairline),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${b.row} · ${b.kind} · ${SessionCard.ageText(b.age(now()))}',
                          style: TextStyle(color: t.accent, fontSize: 11, fontFamily: 'JetBrains Mono')),
                      const SizedBox(height: 4),
                      Text(b.need, style: TextStyle(color: t.text, fontSize: 13)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: Key('clear-${b.id}'),
                          onPressed: () async {
                            final ok = await stepUp('Clear the blocker on ${b.row}');
                            if (!ok) return;
                            await client.clearBlocker(b.id, 'Cleared from the phone');
                            await reload();
                          },
                          child: const Text('Clear'),
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          );
        },
      );
}

/// The grid and today: open rows per project and type, and the day's pace.
class MatrixView extends StatelessWidget {
  const MatrixView({super.key, required this.client});
  final SlateClient client;

  @override
  Widget build(BuildContext context) => Loader<(MatrixData, TodayData)>(
        load: () async => (await client.matrix(), await client.today()),
        builder: (context, data, reload) {
          final t = SlateTokens.of(context);
          final (m, today) = data;
          final head = TextStyle(color: t.text3, fontSize: 11, fontWeight: FontWeight.w600);
          final cell = TextStyle(color: t.text, fontSize: 12);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Today: ${today.closedToday} closed against a ${today.weeklyDailyAverage.toStringAsFixed(1)} a day average, ${today.inFlight} in flight.',
                  key: const Key('today-line'),
                  style: TextStyle(color: today.belowPace ? t.warn : t.text2, fontSize: 13),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    columns: [
                      DataColumn(label: Text('project', style: head)),
                      for (final ty in m.types) DataColumn(label: Text(ty, style: head), numeric: true),
                      DataColumn(label: Text('total', style: head), numeric: true),
                    ],
                    rows: [
                      for (final p in m.projects)
                        DataRow(cells: [
                          DataCell(Text(p, style: cell)),
                          for (final ty in m.types) DataCell(Text('${m.count(p, ty)}', style: cell)),
                          DataCell(Text('${m.projectTotal(p)}', style: cell)),
                        ]),
                      DataRow(cells: [
                        DataCell(Text('all', style: head)),
                        for (final ty in m.types) DataCell(Text('${m.typeTotal(ty)}', style: head)),
                        DataCell(Text('${m.total}', style: head)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}
