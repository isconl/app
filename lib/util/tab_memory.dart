import '../data/db.dart';

/// BI26101519: the last sub-page tab a view was left on, kept per device in the local database so a
/// view reopens where it was. A missing or unreadable value means "use the view's default".
String _key(String view) => 'tab.last.v1.$view';

Future<int?> readTabIndex(AppDb db, String view, int count) async {
  try {
    final v = (await db.getSnapshot(_key(view)))?.$1;
    final i = v is Map ? v['index'] : null;
    if (i is int && i >= 0 && i < count) return i;
  } catch (_) {
    // Nothing stored: the default applies.
  }
  return null;
}

Future<void> writeTabIndex(AppDb db, String view, int index) async {
  try {
    await db.putSnapshot(_key(view), {'index': index});
  } catch (_) {}
}
