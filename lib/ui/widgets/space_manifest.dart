// BI26102890 (Sconl, 28 Oct 2026, adopted; 30 Oct: "do the five items on all the rails"): every space has exactly five
// destinations on its rail. Slot 1 is Overview, slot 5 is Activity, slots 2 to 4 are the space's working destinations.
// The list per space is _kit work/dev/Systems/iSconl/_next/SPACES-five-destinations.md. A space's own view still builds
// its destinations; [fiveDestinations] lays them onto the five slots: a destination that names a slot (or was renamed
// into one, "was X") fills it with its content, a destination with no slot keeps its own name in a free working slot so
// no function is lost, and an empty slot opens an honest screen that says what will live there. Only where the list
// comes from changes; the rail itself is frozen at 0.3.172.
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'space_header.dart';

/// The five destinations of each space, by the id the space passes to [SpaceView].
const Map<String, List<String>> spaceDestinations = {
  'hub': ['Overview', 'Today', 'Notices', 'Services', 'Activity'],
  'slate': ['Overview', 'Grid', 'Asks', 'Register', 'Activity'],
  'calendar': ['Overview', 'Equicycle', 'Month', 'Planner', 'Activity'],
  'compass': ['Overview', 'Now', 'Next', 'Later', 'Activity'],
  'inbox': ['Overview', 'Unread', 'Waiting', 'All', 'Activity'],
  'deck': ['Overview', 'Boards', 'Drafts', 'Sent', 'Activity'],
  'teams': ['Overview', 'Health', 'People', 'Work', 'Activity'],
  'tools': ['Overview', 'Jira', 'Social', 'GitHub', 'Activity'],
  'practice': ['Overview', 'Practices', 'Enquiries', 'Documents', 'Activity'],
  'corporate': ['Overview', 'Entities', 'Work', 'People', 'Activity'],
  'projects-product': ['Overview', 'Building', 'Shipped', 'Platforms', 'Activity'],
  'rhythm': ['Overview', 'Habits', 'Focus', 'Year', 'Activity'],
  'study': ['Overview', 'Campus', 'Tracks', 'Map', 'Activity'],
  'ledger': ['Overview', 'Transactions', 'Plan', 'Assets', 'Activity'],
  'codex': ['Overview', 'Journals', 'Ideas', 'Scans', 'Activity'],
  'settings': ['Overview', 'General', 'Study and notes', 'Account and sync', 'Activity'],
  'hold': ['Overview', 'Browse', 'Shared', 'Device', 'Activity'],
  'accounts': ['Overview', 'Addresses', 'Sign-ups', 'AI seats', 'Activity'],
  'opsec': ['Overview', 'Services', 'Hosts', 'Security', 'Activity'],
};

/// Destinations renamed into a slot by the adopted list ("was X"): space -> old label -> slot.
const Map<String, Map<String, String>> spaceRenames = {
  'hub': {'Now': 'Overview'},
  'rhythm': {'Today': 'Overview'},
  'projects-product': {'Active': 'Overview'},
  'hold': {'Recent': 'Activity'},
  'opsec': {'Health': 'Overview', 'Logs': 'Activity'},
};

/// What each new destination will hold, for its honest empty screen. A label without an entry gets a plain sentence.
const Map<String, String> _plannedFor = {
  'Overview': 'This space at a glance.',
  'Activity': 'What changed in this space, newest first.',
  'Notices': 'Notices from every part of iSconl that need you.',
  'Register': 'The Slate register: every row, searchable.',
  'Practices': 'Your practices and their state.',
  'Platforms': 'The platforms behind the products.',
  'Focus': 'Your focus sessions and what they produced.',
  'Assets': 'What you own and what it is worth.',
  'Shared': 'Share links and the household routes.',
  'Hosts': 'The machines the fleet runs on.',
  'Security': 'Security checks across the fleet.',
  'Now': 'What matters now.',
};

/// True for a destination [fiveDestinations] made because the space has no screen for it yet.
bool isPlannedDestination(SpaceTab t) => t.body is PlannedDestination;

/// Lays a space's own destinations onto its five slots (see the file comment). A space without a list keeps its own.
List<SpaceTab> fiveDestinations(String space, List<SpaceTab> tabs) {
  final slots = spaceDestinations[space];
  if (slots == null) return tabs;
  final renames = spaceRenames[space] ?? const {};
  final out = List<SpaceTab?>.filled(slots.length, null);
  final used = <SpaceTab>{};
  for (var i = 0; i < slots.length; i++) {
    for (final t in tabs) {
      if (used.contains(t)) continue;
      if (t.label == slots[i] || renames[t.label] == slots[i]) {
        out[i] = SpaceTab(slots[i], t.body, icon: t.icon);
        used.add(t);
        break;
      }
    }
  }
  // A destination with no slot keeps its name and content in the first free working slot (2 to 4), then Overview.
  final free = [for (var i = 1; i < slots.length - 1; i++) if (out[i] == null) i, if (out[0] == null) 0];
  final leftovers = [for (final t in tabs) if (!used.contains(t)) t];
  if (leftovers.length > free.length) return tabs; // never drop a destination: keep the space as it was
  for (var k = 0; k < leftovers.length; k++) {
    out[free[k]] = leftovers[k];
  }
  return [
    for (var i = 0; i < slots.length; i++)
      out[i] ?? SpaceTab(slots[i], PlannedDestination(label: slots[i], about: _plannedFor[slots[i]] ?? '')),
  ];
}

/// The first destination that has a real screen, so a space never opens on an empty Overview.
int firstRealDestination(List<SpaceTab> tabs) {
  for (var i = 0; i < tabs.length; i++) {
    if (!isPlannedDestination(tabs[i])) return i;
  }
  return 0;
}

/// An honest empty destination: its name, what will live here, and no sample data.
class PlannedDestination extends StatelessWidget {
  const PlannedDestination({super.key, required this.label, required this.about});
  final String label;
  final String about;

  @override
  Widget build(BuildContext context) => Padding(
        key: ValueKey('planned-destination:$label'),
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: T.title),
          const SizedBox(height: 8),
          if (about.isNotEmpty) Text(about, style: T.body2.copyWith(color: C.text2)),
          const SizedBox(height: 6),
          Text('Not built yet. It will appear here when it is.', style: T.small.copyWith(color: C.text3)),
        ]),
      );
}
