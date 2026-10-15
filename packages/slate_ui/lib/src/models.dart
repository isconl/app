/// A session as slate_sessions reports it.
class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.machine,
    required this.kind,
    required this.lastSeen,
    this.model,
    this.currentRow,
    this.currentRowTitle,
    this.position,
    this.total,
    this.status,
  });

  final String id;
  final String machine;
  final String kind;
  final String? model;
  final String? currentRow;
  final String? currentRowTitle;
  final int? position;
  final int? total;
  final String? status;
  final DateTime lastSeen;

  Duration age(DateTime now) => now.difference(lastSeen);

  /// No check-in for more than 10 minutes (CLAUDE.md section 27).
  bool isStalled(DateTime now) => age(now) > const Duration(minutes: 10) && !isIdle(now);

  /// No check-in for more than 3 hours: its claims are released.
  bool isIdle(DateTime now) => age(now) > const Duration(hours: 3);

  String? get progress =>
      position != null && total != null ? '$position of $total' : null;
}

/// Who a command goes to.
enum TargetScope { session, kindOnMachine, everyone }

class CommandTarget {
  const CommandTarget.session(this.session)
      : scope = TargetScope.session,
        kind = null,
        machine = null;
  const CommandTarget.kindOnMachine({required this.kind, required this.machine})
      : scope = TargetScope.kindOnMachine,
        session = null;
  const CommandTarget.everyone()
      : scope = TargetScope.everyone,
        session = null,
        kind = null,
        machine = null;

  final TargetScope scope;
  final String? session;
  final String? kind;
  final String? machine;

  String get label {
    switch (scope) {
      case TargetScope.session:
        return session!;
      case TargetScope.kindOnMachine:
        return 'every $kind session on $machine';
      case TargetScope.everyone:
        return 'every session on every machine';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CommandTarget &&
      other.scope == scope &&
      other.session == session &&
      other.kind == kind &&
      other.machine == machine;

  @override
  int get hashCode => Object.hash(scope, session, kind, machine);
}

enum QuickAction { windDown, stopForDay, releaseClaims, extendQueue }

extension QuickActionText on QuickAction {
  String get label {
    switch (this) {
      case QuickAction.windDown:
        return 'Wind down';
      case QuickAction.stopForDay:
        return 'Stop for the day';
      case QuickAction.releaseClaims:
        return 'Release claims';
      case QuickAction.extendQueue:
        return 'Extend queue';
    }
  }

  /// The message a quick action sends. Persistent and expiring are set by the
  /// panel, the text stays plain so any session can act on it cold.
  String get message {
    switch (this) {
      case QuickAction.windDown:
        return 'Usage wind-down: finish the atomic step, commit, push, release your claims, check in stopped: usage, then stop.';
      case QuickAction.stopForDay:
        return 'End of day: finish the atomic step, push, release your claims, check in stopped: end of day, then stop.';
      case QuickAction.releaseClaims:
        return 'Release every claim you hold now, with a handoff note on each row, then take the next row.';
      case QuickAction.extendQueue:
        return 'Your queue is being extended. Check in and read slate_queue for the new rows.';
    }
  }
}

/// What the operator is about to send, shown back before step-up.
class CommandDraft {
  const CommandDraft({
    required this.target,
    required this.message,
    required this.persistent,
    this.expiresIn,
    this.action,
  });

  final CommandTarget target;
  final String message;
  final bool persistent;
  final Duration? expiresIn;
  final QuickAction? action;
}

enum DeliveryState { sent, delivered, acknowledged }

class CommandStatus {
  const CommandStatus({required this.id, required this.draft, required this.state});
  final String id;
  final CommandDraft draft;
  final DeliveryState state;

  CommandStatus copyWith(DeliveryState state) =>
      CommandStatus(id: id, draft: draft, state: state);
}
