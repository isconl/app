import 'session_log.dart';

class BetaPrior {
  const BetaPrior({this.alpha = 2.0, this.beta = 2.0});
  final double alpha;
  final double beta;

  double mean(int wins, int total) => (alpha + wins) / (alpha + beta + total);
}

/// Study finish model (BI26101606):
/// Per-user counts with priors (Beta) of finishing, keyed by hour bucket (morning, midday,
/// afternoon, evening, night), block type, energy band, and minutes band.
/// It feeds the scorer's fit term only after 30 logged sessions.
class StudyFinishModel {
  StudyFinishModel({this.prior = const BetaPrior(), this.sessions = const []});
  final BetaPrior prior;
  final List<StudySessionRecord> sessions;

  static const minSessionsForActive = 30;
  bool get isActive => sessions.length >= minSessionsForActive;

  static String hourBucket(int hour) {
    if (hour >= 5 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 14) return 'midday';
    if (hour >= 14 && hour < 18) return 'afternoon';
    if (hour >= 18 && hour < 22) return 'evening';
    return 'night';
  }

  static String energyBand(int? energy) {
    if (energy == null) return 'unknown';
    if (energy <= 3) return 'low';
    if (energy <= 7) return 'medium';
    return 'high';
  }

  static String minutesBand(int minutes) {
    if (minutes <= 15) return 'short';
    if (minutes <= 30) return 'medium';
    if (minutes <= 60) return 'long';
    return 'deep';
  }

  double predictFinishRate({
    required int hour,
    String? blockType,
    int? energy,
    required int minutes,
  }) {
    if (!isActive) return 0.5; // default prior mean before 30 sessions

    final targetHourBucket = hourBucket(hour);
    final targetEnergyBand = energyBand(energy);

    var matchingTotal = 0;
    var matchingFinished = 0;

    for (final s in sessions) {
      if (hourBucket(s.hour) == targetHourBucket &&
          energyBand(s.energy) == targetEnergyBand &&
          (blockType == null || s.blockName == blockType)) {
        matchingTotal++;
        if (s.finished) matchingFinished++;
      }
    }

    if (matchingTotal == 0) {
      for (final s in sessions) {
        if (hourBucket(s.hour) == targetHourBucket) {
          matchingTotal++;
          if (s.finished) matchingFinished++;
        }
      }
    }

    return prior.mean(matchingFinished, matchingTotal);
  }

  String statusString() {
    if (isActive) {
      return 'Active (trained on ${sessions.length} sessions)';
    }
    return 'Off (waiting for 30 sessions, currently ${sessions.length}/$minSessionsForActive)';
  }
}
