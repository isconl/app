import 'package:flutter/material.dart';

import 'backlog.dart';
import 'slate_decisions.dart';
import 'tasks.dart';

/// BI26092327: the menu item formerly called Tasks is Slate, with a tab strip. Tasks is the default
/// tab and renders [TasksView] unchanged, so nothing the old view did is lost. Decisions is an honest placeholder,
/// and Register is the drive-wide rollup that was Systems > Backlog (BI26100540: one Slate entry) until the Slate integration lands, the same shape as the web
/// console's renderSlate(): no fake data. The chosen tab is remembered for the life of the app
/// (the web console remembers it per browser).
enum SlateTab { tasks, decisions, register }

class SlateView extends StatefulWidget {
  const SlateView({super.key});

  /// The tab last shown, kept across rebuilds and navigation for the life of the app.
  static SlateTab remembered = SlateTab.tasks;

  @override
  State<SlateView> createState() => _SlateViewState();
}

class _SlateViewState extends State<SlateView> {
  late SlateTab _tab = SlateView.remembered;

  String _label(SlateTab t) => switch (t) {
        SlateTab.tasks => 'Tasks',
        SlateTab.decisions => 'Decisions',
        SlateTab.register => 'Register',
      };

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
          SlateTab.tasks => const TasksView(),
          SlateTab.decisions => const DecisionsView(),
          SlateTab.register => const BacklogView(),
        },
      ],
    );
  }
}
