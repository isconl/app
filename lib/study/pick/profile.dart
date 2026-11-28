// The weights of the study score (profile isconl.study@1). Shipped in the app as defaultStudyProfileJson, replaceable
// from the server: StudyProfile.parse falls back to the shipped copy when a replacement is unreadable.
import 'dart:convert';

class StudyProfile {
  final String id;
  final double coverage;
  final double momentum;
  final double fit;
  final double relevance;
  final double review;
  final double announcement;

  /// Coverage weight multiplier when a track is more than one cycle behind its pace.
  final double coverageOverride;

  /// Added to a candidate whose track has no pick yet and the cycle is in its last two days.
  final double trackGuarantee;
  final int hourlyRateMinSessions;
  final int defaultWindowMinutes;
  final double targetWeeks;
  final List<int> reviewCurveDays;

  const StudyProfile({
    this.id = 'isconl.study@1',
    this.coverage = 1.0,
    this.momentum = 0.5,
    this.fit = 1.5,
    this.relevance = 0.6,
    this.review = 0.8,
    this.announcement = 0.7,
    this.coverageOverride = 3.0,
    this.trackGuarantee = 100,
    this.hourlyRateMinSessions = 30,
    this.defaultWindowMinutes = 45,
    this.targetWeeks = 26,
    this.reviewCurveDays = const [1, 3, 7, 21],
  });

  static const defaultStudyProfileJson = '{"id":"isconl.study@1","weights":{"coverage":1.0,"momentum":0.5,"fit":1.5,'
      '"relevance":0.6,"review":0.8,"announcement":0.7},"coverageOverride":3.0,"trackGuarantee":100,'
      '"hourlyRateMinSessions":30,"defaultWindowMinutes":45,"targetWeeks":26,"reviewCurveDays":[1,3,7,21]}';

  factory StudyProfile.fromJson(Map<String, dynamic> j) {
    final w = (j['weights'] as Map<String, dynamic>?) ?? const {};
    double d(Object? v, double dflt) => v is num ? v.toDouble() : dflt;
    const base = StudyProfile();
    final curve = (j['reviewCurveDays'] as List?)?.map((e) => (e as num).toInt()).toList();
    return StudyProfile(
      id: (j['id'] ?? base.id) as String,
      coverage: d(w['coverage'], base.coverage),
      momentum: d(w['momentum'], base.momentum),
      fit: d(w['fit'], base.fit),
      relevance: d(w['relevance'], base.relevance),
      review: d(w['review'], base.review),
      announcement: d(w['announcement'], base.announcement),
      coverageOverride: d(j['coverageOverride'], base.coverageOverride),
      trackGuarantee: d(j['trackGuarantee'], base.trackGuarantee),
      hourlyRateMinSessions: (j['hourlyRateMinSessions'] as num?)?.toInt() ?? base.hourlyRateMinSessions,
      defaultWindowMinutes: (j['defaultWindowMinutes'] as num?)?.toInt() ?? base.defaultWindowMinutes,
      targetWeeks: d(j['targetWeeks'], base.targetWeeks),
      reviewCurveDays: (curve == null || curve.isEmpty) ? base.reviewCurveDays : curve,
    );
  }

  /// Reads a replacement profile; anything unreadable gives the shipped one, never an exception on the pick path.
  static StudyProfile parse(String? raw) {
    try {
      if (raw != null && raw.isNotEmpty) return StudyProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    return StudyProfile.fromJson(jsonDecode(defaultStudyProfileJson) as Map<String, dynamic>);
  }
}
