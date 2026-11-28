/// BI26100157 (the keyboard slice): the views a person has opened in the desktop shell, so Alt+Left and
/// Alt+Right (and Escape with nothing open) step back and forward the way the console's history does
/// (hub `app.js`: "Alt+Left / Alt+Right mirror the browser, and Escape steps back once nothing is open").
///
/// Pure Dart, no widgets: opening a view drops anything ahead of it, the same view twice in a row is one
/// entry, and the list is capped so a long session cannot grow it without end.
class ViewHistory {
  ViewHistory(String first) : _entries = [first];

  /// The most views kept; the oldest go first.
  static const int cap = 50;

  final List<String> _entries;
  int _at = 0;

  String get current => _entries[_at];
  bool get canBack => _at > 0;
  bool get canForward => _at < _entries.length - 1;

  /// A view was opened. Returns false when it is the view already showing.
  bool open(String id) {
    if (id == current) return false;
    _entries.removeRange(_at + 1, _entries.length);
    _entries.add(id);
    if (_entries.length > cap) _entries.removeAt(0);
    _at = _entries.length - 1;
    return true;
  }

  /// The view one step back, or null at the start.
  String? back() {
    if (!canBack) return null;
    _at--;
    return current;
  }

  /// The view one step forward, or null at the end.
  String? forward() {
    if (!canForward) return null;
    _at++;
    return current;
  }
}

/// The view a web address asks for: `#/inbox` or `#inbox` names a view id. Anything that is not a plain
/// id (letters, digits, `-` and `_`) is ignored, so a crafted fragment can only ever pick a known view.
String? viewFromFragment(String fragment) {
  final id = fragment.startsWith('/') ? fragment.substring(1) : fragment;
  if (id.isEmpty || id.length > 40) return null;
  return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ? id : null;
}
