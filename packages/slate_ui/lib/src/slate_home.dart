import 'package:flutter/material.dart';

import 'blockers_matrix_views.dart';
import 'client.dart';
import 'command_panel.dart';
import 'queue_views.dart';
import 'rows_views.dart';
import 'sessions_board.dart';

enum SlateSection { sessions, commands, rows, decisions, brainstorms, blockers, matrix }

extension SlateSectionLabel on SlateSection {
  String get label => switch (this) {
        SlateSection.sessions => 'Sessions',
        SlateSection.commands => 'Commands',
        SlateSection.rows => 'Rows',
        SlateSection.decisions => 'Decisions',
        SlateSection.brainstorms => 'Brainstorms',
        SlateSection.blockers => 'Blockers',
        SlateSection.matrix => 'Matrix',
      };
}

/// All of slate in one widget: a chip strip over the seven sections. The host
/// supplies the client and two step-up callbacks; everything else lives here.
class SlateHome extends StatefulWidget {
  const SlateHome({
    super.key,
    required this.client,
    required this.commandStepUp,
    required this.writeStepUp,
    this.initial = SlateSection.sessions,
  });

  final SlateClient client;
  final StepUp commandStepUp;
  final WriteStepUp writeStepUp;
  final SlateSection initial;

  @override
  State<SlateHome> createState() => _SlateHomeState();
}

class _SlateHomeState extends State<SlateHome> {
  late SlateSection _section = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return Column(children: [
      SizedBox(
        height: 44,
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          for (final s in SlateSection.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('section-${s.name}'),
                label: Text(s.label),
                selected: _section == s,
                onSelected: (_) => setState(() => _section = s),
              ),
            ),
        ])),
      ),
      Expanded(
        child: switch (_section) {
          SlateSection.sessions => SessionsBoard(client: c),
          SlateSection.commands => CommandPanel(client: c, stepUp: widget.commandStepUp),
          SlateSection.rows => RowsView(client: c, stepUp: widget.writeStepUp),
          SlateSection.decisions => DecisionsView(client: c, stepUp: widget.writeStepUp),
          SlateSection.brainstorms => BrainstormsView(client: c, stepUp: widget.writeStepUp),
          SlateSection.blockers => BlockersView(client: c, stepUp: widget.writeStepUp),
          SlateSection.matrix => MatrixView(client: c),
        },
      ),
    ]);
  }
}
