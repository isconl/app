/// BI26101207: the Trajectory module's forecast block (course standard 4.2.0
/// section 17), as the module payload serves it. The app reads only this parsed
/// block and never the markdown table, so the numbers on screen are the block's.
library;

/// How far past its re-score date a forecast may run before it is called stale.
const staleAfterDays = 30;

/// score = p x impact / 100, kept to two decimals (p is a percentage, impact 1 to 5).
double scenarioScore(num p, num impact) => (p * impact / 100 * 100).round() / 100;

/// The score as shown: two decimals, always.
String scoreText(num p, num impact) => scenarioScore(p, impact).toStringAsFixed(2);

/// More than [staleAfterDays] days after [rescoreOn]. A missing or unreadable
/// date is never called stale: the badge claims something, so it needs a date.
bool isStaleForecast(DateTime? rescoreOn, DateTime now) =>
    rescoreOn != null && now.difference(rescoreOn).inDays > staleAfterDays;

/// A 1 to 5 value as a dot count, clamped so a bad block cannot draw 9 dots.
int dotCount(num v) => v.round().clamp(1, 5);

DateTime? parseDate(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  return DateTime.tryParse(v.trim());
}

class TrajectoryScenario {
  const TrajectoryScenario({
    required this.id,
    required this.name,
    required this.p,
    required this.impact,
    required this.control,
    required this.signal,
    required this.basis,
    required this.indicators,
    required this.now,
  });

  final String id;
  final String name;

  /// Likelihood, a whole-number percentage.
  final int p;
  final int impact;
  final int control;
  final String signal;
  final String basis;
  final List<String> indicators;

  /// What to do now.
  final String now;

  double get score => scenarioScore(p, impact);
  String get scoreLabel => scoreText(p, impact);

  factory TrajectoryScenario.fromJson(Map<String, dynamic> j) => TrajectoryScenario(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        p: ((j['p'] as num?) ?? 0).round().clamp(0, 100),
        impact: ((j['impact'] as num?) ?? 1).round(),
        control: ((j['control'] as num?) ?? 1).round(),
        signal: '${j['signal'] ?? ''}',
        basis: '${j['basis'] ?? ''}',
        indicators: [for (final e in (j['indicators'] is List ? j['indicators'] as List : const [])) '$e'],
        now: '${j['now'] ?? ''}',
      );
}

class TrajectoryPattern {
  const TrajectoryPattern(this.id, this.strength);
  final String id;
  final String strength;
}

class Trajectory {
  const Trajectory({
    required this.question,
    required this.horizon90d,
    required this.horizon12m,
    required this.rescoreOn,
    required this.rescoreOnText,
    required this.patterns,
    required this.scenarios,
    required this.register,
    required this.sconlOnly,
  });

  final String question;
  final DateTime? horizon90d;
  final DateTime? horizon12m;
  final DateTime? rescoreOn;
  final String rescoreOnText;
  final List<TrajectoryPattern> patterns;
  final List<TrajectoryScenario> scenarios;

  /// Register rows. Shown only when [sconlOnly] is false.
  final List<String> register;

  /// The module's SCONL_ONLY flag: true unless it says `no`.
  final bool sconlOnly;

  bool isStale(DateTime now) => isStaleForecast(rescoreOn, now);

  /// Parses the block the payload serves. Returns null when [v] is not a block
  /// with at least one scenario, so a module without one shows nothing.
  static Trajectory? tryParse(Object? v, {Object? sconlOnly}) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final raw = j['scenarios'];
    if (raw is! List || raw.isEmpty) return null;
    final reg = j['register'];
    return Trajectory(
      question: '${j['question'] ?? ''}',
      horizon90d: parseDate(j['horizon_90d']),
      horizon12m: parseDate(j['horizon_12m']),
      rescoreOn: parseDate(j['rescore_on']),
      rescoreOnText: '${j['rescore_on'] ?? ''}',
      patterns: [
        for (final p in (j['patterns'] is List ? j['patterns'] as List : const []))
          if (p is Map) TrajectoryPattern('${p['id'] ?? ''}', '${p['strength'] ?? ''}'),
      ],
      scenarios: [
        for (final s in raw)
          if (s is Map) TrajectoryScenario.fromJson(Map<String, dynamic>.from(s)),
      ],
      register: [
        for (final r in (reg is List ? reg : const []))
          r is Map ? '${r['text'] ?? r['row'] ?? ''}' : '$r',
      ],
      // Only an explicit `no` opens the register; anything else keeps it closed.
      sconlOnly: '${sconlOnly ?? j['sconl_only'] ?? 'yes'}'.toLowerCase() != 'no',
    );
  }
}

/// A learner's own forecast before they see the table.
class ProbeEntry {
  const ProbeEntry(this.pct, this.at);
  final int pct;
  final DateTime at;

  Map<String, dynamic> toJson() => {'pct': pct, 'at': at.toUtc().toIso8601String()};

  static ProbeEntry? fromJson(Object? v) {
    if (v is! Map) return null;
    final pct = v['pct'];
    final at = parseDate(v['at']);
    if (pct is! num || at == null) return null;
    return ProbeEntry(pct.round(), at);
  }
}

/// Whole-number percentage 0 to 100, or null for anything else.
int? parseProbe(String text) {
  final t = text.trim().replaceAll('%', '').trim();
  if (!RegExp(r'^\d{1,3}$').hasMatch(t)) return null;
  final n = int.parse(t);
  return n > 100 ? null : n;
}
