import 'package:flutter/material.dart';

import '../widgets/space_header.dart';
import 'package:slate_ui/slate_ui.dart';

import '../../app_scope.dart';
import '../../util/fmt.dart' as fmt;
import '../../services/slate_hub_client.dart';
import 'slate_tabs.dart';

/// BS26102104: Slate is three tabs on the phone: Overview (the dashboard), Grid (projects by type, a cell opens its rows)
/// and Asks (decisions, manual activities, blockers, runbook approvals). Sessions and commands, Tasks and the Register
/// open from the Overview. The tab last shown is remembered for the life of the app.
enum SlateTab { overview, grid, asks }

class SlateView extends StatelessWidget {
  const SlateView({super.key});

  /// The tab last shown, kept across rebuilds and navigation for the life of the app.
  static SlateTab remembered = SlateTab.overview;

  static String label(SlateTab t) => switch (t) {
        SlateTab.overview => 'Overview',
        SlateTab.grid => 'Grid',
        SlateTab.asks => 'Asks',
      };

  /// BI26101814: the search finds a task or a register row and sends Slate to the tab that holds it.
  static List<SpaceHit> hitsFor(BuildContext context) {
    final store = AppScope.of(context).store;
    return [
      for (final t in fmt.lm(fmt.m(store.state.value)['tasks']))
        if (fmt.s(t['TITLE']).isNotEmpty)
          SpaceHit(
            title: fmt.s(t['TITLE']),
            subtitle: [fmt.s(t['ID']), fmt.s(t['TAG'])].where((x) => x.isNotEmpty).join(' · '),
            tab: SlateTab.overview.index,
          ),
      for (final p in fmt.lm(fmt.m(store.backlog.value)['projects']))
        for (final r in fmt.lm(p['rows']))
          SpaceHit(
            title: fmt.s(r['title']),
            subtitle: [fmt.s(r['id']), fmt.s(p['project']), fmt.s(r['status'])].where((x) => x.isNotEmpty).join(' · '),
            tab: SlateTab.grid.index,
          ),
    ];
  }

  SlateClient _client(BuildContext context) => HubSlateClient(AppScope.of(context).api);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final client = _client(context);
    final write = passkeyWriteStepUp(app.api, app.session.passkeys);
    return SpaceView(
      space: 'slate',
      searchHint: 'Search tasks and register rows',
      initialTab: remembered.index,
      hits: hitsFor,
      tabs: [
        SpaceTab(label(SlateTab.overview), SlateOverviewTab(
          client: client,
          agents: null,
          commandStepUp: passkeyStepUp(app.api, app.session.passkeys),
          writeStepUp: write,
        )),
        SpaceTab(label(SlateTab.grid), SlateGridTab(client: client, writeStepUp: write)),
        SpaceTab(label(SlateTab.asks), SlateAsksTab(client: client, writeStepUp: write)),
      ],
    );
  }
}
