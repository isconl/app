/// Track pace forecast (BI26101606):
/// Per track, the finish date at the last four cycles' pace against the target date;
/// a track forecast to miss by more than two cycles is flagged on its ring.
class TrackPaceForecast {
  const TrackPaceForecast({
    required this.trackId,
    required this.trackLabel,
    required this.unreadMinutes,
    required this.targetDate,
    required this.cyclesPaceMinutes,
    required this.forecastFinishDate,
    required this.isMissByTwoCycles,
  });

  final String trackId;
  final String trackLabel;
  final double unreadMinutes;
  final DateTime targetDate;
  final double cyclesPaceMinutes;
  final DateTime forecastFinishDate;
  final bool isMissByTwoCycles;

  static TrackPaceForecast calculate({
    required String trackId,
    required String trackLabel,
    required double unreadMinutes,
    required DateTime targetDate,
    required List<double> lastFourCyclesMinutes,
    required DateTime now,
    int cycleLengthDays = 7,
  }) {
    final avgPace = lastFourCyclesMinutes.isEmpty
        ? 30.0
        : lastFourCyclesMinutes.reduce((a, b) => a + b) / lastFourCyclesMinutes.length;

    final cyclesNeeded = avgPace > 0 ? (unreadMinutes / avgPace).ceil() : 52;
    final forecastDate = now.add(Duration(days: cyclesNeeded * cycleLengthDays));
    final diffDays = forecastDate.difference(targetDate).inDays;
    final isMiss = diffDays > (2 * cycleLengthDays);

    return TrackPaceForecast(
      trackId: trackId,
      trackLabel: trackLabel,
      unreadMinutes: unreadMinutes,
      targetDate: targetDate,
      cyclesPaceMinutes: avgPace,
      forecastFinishDate: forecastDate,
      isMissByTwoCycles: isMiss,
    );
  }
}
