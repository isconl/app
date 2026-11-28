import 'pick/models.dart';

class BeforeTheRoomPick {
  const BeforeTheRoomPick({
    required this.eventTitle,
    required this.eventTime,
    required this.moduleCard,
    required this.matchedSubject,
  });

  final String eventTitle;
  final DateTime eventTime;
  final ModuleCard moduleCard;
  final String matchedSubject;

  String get label => 'Before the room: $eventTitle';
}

/// Before-the-room service (BI26101606):
/// For each calendar event in the next 48 hours whose title or attendees match a subject,
/// a pick two days ahead, labelled with the event.
class BeforeTheRoomService {
  const BeforeTheRoomService();

  List<BeforeTheRoomPick> findPicks({
    required DateTime now,
    required List<Map<String, dynamic>> events,
    required List<ModuleCard> cards,
  }) {
    final out = <BeforeTheRoomPick>[];
    final windowEnd = now.add(const Duration(hours: 48));

    for (final ev in events) {
      final title = (ev['title'] ?? ev['summary'] ?? '').toString();
      final attendees = (ev['attendees'] as List? ?? const []).map((e) => e.toString().toLowerCase()).toList();
      final dtStr = (ev['start'] ?? ev['at'] ?? '').toString();
      final evTime = DateTime.tryParse(dtStr) ?? now.add(const Duration(hours: 24));

      if (evTime.isBefore(now) || evTime.isAfter(windowEnd)) continue;

      final titleLower = title.toLowerCase();

      for (final card in cards) {
        for (final subj in card.subjects) {
          final subjLower = subj.toLowerCase();
          if (titleLower.contains(subjLower) || attendees.any((a) => a.contains(subjLower))) {
            out.add(BeforeTheRoomPick(
              eventTitle: title,
              eventTime: evTime,
              moduleCard: card,
              matchedSubject: subj,
            ));
            break;
          }
        }
      }
    }
    return out;
  }
}
