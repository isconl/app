import '../../util/fmt.dart' as fmt;

/// BI26100129: what the Projects landing can show from rows the app already
/// holds: the portfolio split by category. The booking funnel, leads and
/// Slate movement need the hub aggregate (`GET /api/dash/projects`, filed as
/// its own row); until it exists those tiles say so instead of showing a
/// number nobody computed.
class ProjectsDash {
  ProjectsDash(this.byCategory, this.total);
  final Map<String, int> byCategory;
  final int total;

  static const categories = ['Practice', 'Corporate', 'Product', 'Platform'];

  static String categoryOf(Map<String, dynamic> p) {
    final c = fmt.s(p['CATEGORY'] ?? p['TYPE'] ?? p['cat']).toLowerCase();
    if (c.contains('practice')) return 'Practice';
    if (c.contains('corporate')) return 'Corporate';
    if (c.contains('platform')) return 'Platform';
    if (c.contains('product')) return 'Product';
    return 'Other';
  }

  static ProjectsDash from(List<Map<String, dynamic>> projects, {int corporateCount = 0}) {
    final by = {for (final c in [...categories, 'Other']) c: 0};
    for (final p in projects) {
      final c = categoryOf(p);
      by[c] = by[c]! + 1;
    }
    if (corporateCount > 0 && by['Corporate'] == 0) by['Corporate'] = corporateCount;
    by.removeWhere((k, v) => k == 'Other' && v == 0);
    return ProjectsDash(by, by.values.fold(0, (a, b) => a + b));
  }
}
