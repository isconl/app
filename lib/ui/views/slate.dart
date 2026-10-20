import 'package:flutter/material.dart';

import '../widgets/space_header.dart';
import 'package:slate_ui/slate_ui.dart';

import '../../app_scope.dart';
import '../../util/fmt.dart' as fmt;
import '../../services/slate_hub_client.dart';
import 'backlog.dart';
import 'tasks.dart';

/// BI26092327: the menu item formerly called Tasks is Slate, with a tab strip. Tasks is the default
/// tab and renders [TasksView] unchanged, so nothing the old view did is lost. Decisions is an honest placeholder,
/// and Register is the drive-wide rollup that was Systems > Backlog (BI26100540: one Slate entry) until the Slate integration lands, the same shape as the web
/// console's renderSlate(): no fake data. The chosen tab is remembered for the life of the app
/// (the web console remembers it per browser).
enum SlateTab { slate, tasks, register }

class SlateView extends StatelessWidget {
  const SlateView({super.key});

  /// The tab last shown, kept across rebuilds and navigation for the life of the app.
  static SlateTab remembered = SlateTab.slate;

  static String label(SlateTab t) => switch (t) {
        SlateTab.slate => 'Command',
        SlateTab.tasks => 'Tasks',
        SlateTab.register => 'Register',
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
            tab: SlateTab.tasks.index,
          ),
      for (final p in fmt.lm(fmt.m(store.backlog.value)['projects']))
        for (final r in fmt.lm(p['rows']))
          SpaceHit(
            title: fmt.s(r['title']),
            subtitle: [fmt.s(r['id']), fmt.s(p['project']), fmt.s(r['status'])].where((x) => x.isNotEmpty).join(' · '),
            tab: SlateTab.register.index,
          ),
    ];
  }

  SlateClient _client(BuildContext context) => HubSlateClient(AppScope.of(context).api);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SpaceView(
      space: 'slate',
      searchHint: 'Search tasks and register rows',
      initialTab: remembered.index,
      hits: hitsFor,
      tabs: [
        SpaceTab(label(SlateTab.slate), SlateHome(
          client: _client(context),
          commandStepUp: passkeyStepUp(app.api, app.session.passkeys),
          writeStepUp: passkeyWriteStepUp(app.api, app.session.passkeys),
        )),
        SpaceTab(label(SlateTab.tasks), const TasksView()),
        SpaceTab(label(SlateTab.register), const BacklogView()),
      ],
    );
  }
}
