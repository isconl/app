import 'package:flutter/material.dart';
import 'package:slate_ui/slate_ui.dart';

import '../../app_scope.dart';
import '../../services/slate_hub_client.dart';
import 'backlog.dart';
import 'tasks.dart';

/// BI26092327: the menu item formerly called Tasks is Slate, with a tab strip. Tasks is the default
/// tab and renders [TasksView] unchanged, so nothing the old view did is lost. Decisions is an honest placeholder,
/// and Register is the drive-wide rollup that was Systems > Backlog (BI26100540: one Slate entry) until the Slate integration lands, the same shape as the web
/// console's renderSlate(): no fake data. The chosen tab is remembered for the life of the app
/// (the web console remembers it per browser).
enum SlateTab { slate, tasks, register }

class SlateView extends StatefulWidget {
  const SlateView({super.key});

  /// The tab last shown, kept across rebuilds and navigation for the life of the app.
  static SlateTab remembered = SlateTab.slate;

  @override
  State<SlateView> createState() => _SlateViewState();
}

class _SlateViewState extends State<SlateView> {
  late SlateTab _tab = SlateView.remembered;

  String _label(SlateTab t) => switch (t) {
        SlateTab.slate => 'Command',
        SlateTab.tasks => 'Tasks',
        SlateTab.register => 'Register',
      };

  SlateClient _client(BuildContext context) => HubSlateClient(AppScope.of(context).api);

  /// slate_ui's widgets scroll themselves, so they need a bounded height inside this Column.
  Widget _bounded(BuildContext context, Widget child) =>
      SizedBox(height: (MediaQuery.of(context).size.height - 260).clamp(360.0, 4000.0), child: child);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final t in SlateTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_label(t)),
                    selected: _tab == t,
                    onSelected: (_) => setState(() {
                      _tab = t;
                      SlateView.remembered = t;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        switch (_tab) {
          SlateTab.slate => _bounded(
              context,
              SlateHome(
                client: _client(context),
                commandStepUp: passkeyStepUp(AppScope.of(context).api, AppScope.of(context).session.passkeys),
                writeStepUp: passkeyWriteStepUp(AppScope.of(context).api, AppScope.of(context).session.passkeys),
              )),
          SlateTab.tasks => const TasksView(),
          SlateTab.register => const BacklogView(),
        },
      ],
    );
  }
}
