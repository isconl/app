import 'package:flutter/material.dart';

import '../../data/destinations.dart';
import '../../theme.dart';

/// Maps Material icon name strings from the destinations manifest
/// to Flutter IconData. Falls back to a circle for unknown names.
const spaceTabIcons = <String, IconData>{
  'grid_view': Icons.grid_view_rounded,
  'history': Icons.history_rounded,
  'bolt': Icons.bolt_rounded,
  'today': Icons.today_rounded,
  'dns': Icons.dns_rounded,
  'terminal': Icons.terminal_rounded,
  'task_alt': Icons.task_alt_rounded,
  'list_alt': Icons.list_alt_rounded,
  'calendar_month': Icons.calendar_month_rounded,
  'event': Icons.event_rounded,
  'download': Icons.download_rounded,
  'center_focus_strong': Icons.center_focus_strong_rounded,
  'skip_next': Icons.skip_next_rounded,
  'schedule': Icons.schedule_rounded,
  'mark_email_unread': Icons.mark_email_unread_rounded,
  'notifications': Icons.notifications_rounded,
  'tune': Icons.tune_rounded,
  'forum': Icons.forum_rounded,
  'help_outline': Icons.help_outline_rounded,
  'snooze': Icons.snooze_rounded,
  'chat': Icons.chat_rounded,
  'contacts': Icons.contacts_rounded,
  'dashboard': Icons.dashboard_rounded,
  'edit_note': Icons.edit_note_rounded,
  'check_circle': Icons.check_circle_rounded,
  'corporate_fare': Icons.corporate_fare_rounded,
  'people': Icons.people_rounded,
  'view_kanban': Icons.view_kanban_rounded,
  'share': Icons.share_rounded,
  'code': Icons.code_rounded,
  'hub': Icons.hub_rounded,
  'description': Icons.description_rounded,
  'handshake': Icons.handshake_rounded,
  'verified': Icons.verified_rounded,
  'inventory_2': Icons.inventory_2_rounded,
  'map': Icons.map_rounded,
  'new_releases': Icons.new_releases_rounded,
  'view_agenda': Icons.view_agenda_rounded,
  'repeat': Icons.repeat_rounded,
  'person': Icons.person_rounded,
  'psychology': Icons.psychology_rounded,
  'gavel': Icons.gavel_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'flag': Icons.flag_rounded,
  'savings': Icons.savings_rounded,
  'school': Icons.school_rounded,
  'library_books': Icons.library_books_rounded,
  'note': Icons.note_rounded,
  'auto_stories': Icons.auto_stories_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'qr_code_scanner': Icons.qr_code_scanner_rounded,
  'event_note': Icons.event_note_rounded,
  'vpn_key': Icons.vpn_key_rounded,
  'track_changes': Icons.track_changes_rounded,
  'folder_open': Icons.folder_open_rounded,
  'smartphone': Icons.smartphone_rounded,
  'library_music': Icons.library_music_rounded,
  'mic': Icons.mic_rounded,
  'queue_music': Icons.queue_music_rounded,
  'list': Icons.list_rounded,
  'settings': Icons.settings_rounded,
  'policy': Icons.policy_rounded,
  'radio_button_unchecked': Icons.radio_button_unchecked_rounded,
  'inventory': Icons.inventory_rounded,
  'apps': Icons.apps_rounded,
  'layers': Icons.layers_rounded,
  'miscellaneous_services': Icons.miscellaneous_services_rounded,
  'eco': Icons.eco_rounded,
  'public': Icons.public_rounded,
  'newspaper': Icons.newspaper_rounded,
  'manage_accounts': Icons.manage_accounts_rounded,
  'info': Icons.info_rounded,
  'monitoring': Icons.monitoring_rounded,
  'warning': Icons.warning_rounded,
  'group_work': Icons.group_work_rounded,
};

/// Resolves a Material icon name to an IconData, with a circle fallback.
IconData iconForName(String name) =>
    spaceTabIcons[name] ?? Icons.circle_outlined;

/// The five-destination view for a space. Takes its destinations from
/// the manifest (one source, drawn twice: phone rail + web tab strip).
///
/// BI26102802: draws either a tab row or a floating pill rail depending
/// on [SpaceNavMode]. This widget changes only WHERE its list comes from
/// (the manifest), not its look or behaviour.
class SpaceView extends StatefulWidget {
  const SpaceView({
    super.key,
    required this.viewKey,
    required this.destinations,
    required this.builders,
  });

  /// The nav.json view key for this space (e.g. 'tasks', 'learning').
  final String viewKey;

  /// The five destinations from the manifest.
  final List<Destination> destinations;

  /// A builder per destination key. Keys not in this map get an
  /// honest empty state saying what will live there.
  final Map<String, Widget Function()> builders;

  @override
  State<SpaceView> createState() => _SpaceViewState();
}

class _SpaceViewState extends State<SpaceView> {
  int _current = 0;
  final Map<int, Widget> _built = {};

  @override
  Widget build(BuildContext context) {
    // Build the current destination lazily and keep it (IndexedStack).
    if (!_built.containsKey(_current)) {
      final dest = widget.destinations[_current];
      final builder = widget.builders[dest.key];
      _built[_current] = builder != null
          ? builder()
          : _EmptyDestination(destination: dest);
    }

    return Column(
      children: [
        _DestinationStrip(
          destinations: widget.destinations,
          current: _current,
          onSelect: (i) => setState(() => _current = i),
        ),
        Expanded(
          child: IndexedStack(
            index: _current,
            children: [
              for (var i = 0; i < widget.destinations.length; i++)
                _built[i] ?? const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontal strip of five destination buttons.
class _DestinationStrip extends StatelessWidget {
  const _DestinationStrip({
    required this.destinations,
    required this.current,
    required this.onSelect,
  });

  final List<Destination> destinations;
  final int current;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(color: C.bg),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: destinations.length,
        itemBuilder: (context, i) {
          final selected = i == current;
          final dest = destinations[i];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected ? C.greenBg : Colors.transparent,
                borderRadius: BorderRadius.circular(Sz.rSm),
                border: selected ? Border.all(color: C.greenDim) : null,
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      iconForName(dest.icon),
                      size: 14,
                      color: selected ? C.greenBright : C.text3,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      dest.label,
                      style: (selected
                              ? T.body2.copyWith(
                                  color: C.greenBright,
                                  fontWeight: FontWeight.w600)
                              : T.body2)
                          .copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Honest empty state for a destination whose screen does not exist yet.
class _EmptyDestination extends StatelessWidget {
  const _EmptyDestination({required this.destination});
  final Destination destination;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconForName(destination.icon), size: 48, color: C.text3),
          const SizedBox(height: 16),
          Text(
            destination.label,
            style: T.title.copyWith(color: C.text2),
          ),
          const SizedBox(height: 8),
          Text(
            'This section is on its way.',
            style: T.body2.copyWith(color: C.text3),
          ),
        ],
      ),
    );
  }
}
