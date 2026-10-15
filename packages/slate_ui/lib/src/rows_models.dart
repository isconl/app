/// A row as slate_list reports it.
class RowSummary {
  const RowSummary({
    required this.id,
    required this.project,
    required this.type,
    required this.title,
    required this.status,
    this.priority,
    this.claimedBy,
    this.gate,
    this.subset,
  });

  final String id;
  final String project;
  final String type;
  final String title;
  final String status;
  final int? priority;
  final String? claimedBy;

  /// A person gate such as `sconl:decision` or `sconl:brainstorm`.
  final String? gate;
  final String? subset;

  bool get isClaimed => claimedBy != null && claimedBy!.isNotEmpty;
}

/// One row in full.
class RowDetail extends RowSummary {
  const RowDetail({
    required super.id,
    required super.project,
    required super.type,
    required super.title,
    required super.status,
    required this.body,
    super.priority,
    super.claimedBy,
    super.gate,
    super.subset,
  });

  final String body;
}

class BlockerInfo {
  const BlockerInfo({
    required this.id,
    required this.row,
    required this.kind,
    required this.need,
    required this.raisedAt,
  });

  final String id;
  final String row;

  /// decision, hands, command, access or external.
  final String kind;
  final String need;
  final DateTime raisedAt;

  Duration age(DateTime now) => now.difference(raisedAt);
}

/// Open rows per project and type, as slate_matrix returns them.
class MatrixData {
  const MatrixData({required this.types, required this.cells});

  final List<String> types;

  /// project -> type -> count.
  final Map<String, Map<String, int>> cells;

  List<String> get projects => cells.keys.toList()..sort();
  int count(String project, String type) => cells[project]?[type] ?? 0;
  int projectTotal(String project) =>
      types.fold(0, (a, t) => a + count(project, t));
  int typeTotal(String type) =>
      cells.keys.fold(0, (a, p) => a + count(p, type));
  int get total => types.fold(0, (a, t) => a + typeTotal(t));
}

/// The one-paragraph state of the day.
class TodayData {
  const TodayData({
    required this.closedToday,
    required this.weeklyDailyAverage,
    required this.inFlight,
  });

  final int closedToday;
  final double weeklyDailyAverage;
  final int inFlight;

  bool get belowPace => closedToday < weeklyDailyAverage * 0.5;
}
