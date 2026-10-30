/// BI26092648: which face the Console card shows, and how a double-tap changes it.
library;

enum ConsoleMode {
  progress,
  player,
  recorder;

  ConsoleMode get next => ConsoleMode.values[(index + 1) % ConsoleMode.values.length];

  /// The word after "Console" in the pill; none for Progress, which is the card as it was.
  String? get pillSuffix => switch (this) {
        ConsoleMode.progress => null,
        ConsoleMode.player => 'Player',
        ConsoleMode.recorder => 'Recorder',
      };

  static ConsoleMode parse(Object? raw) {
    for (final m in ConsoleMode.values) {
      if (m.name == raw) return m;
    }
    return ConsoleMode.progress;
  }
}

/// Detects two taps close together. Pure: the caller supplies the time of each tap.
class DoubleTapDetector {
  DoubleTapDetector({this.gap = const Duration(milliseconds: 300)});

  /// The longest pause between two taps that still counts as one run.
  final Duration gap;

  int _count = 0;
  DateTime? _last;

  /// Registers a tap. Returns true on the second tap of a run and starts over.
  bool tap(DateTime now) {
    final last = _last;
    if (last == null || now.difference(last) > gap) _count = 0;
    _count++;
    _last = now;
    if (_count >= 2) {
      _count = 0;
      _last = null;
      return true;
    }
    return false;
  }
}

/// Where the last mode is kept; the app backs it with its snapshot table.
abstract class ConsoleKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class ConsoleModeController {
  ConsoleModeController(this._store);

  final ConsoleKeyValue _store;
  static const _key = 'console.mode';

  ConsoleMode mode = ConsoleMode.progress;
  final _listeners = <void Function(ConsoleMode)>[];

  void addListener(void Function(ConsoleMode) l) => _listeners.add(l);
  void removeListener(void Function(ConsoleMode) l) => _listeners.remove(l);

  Future<void> restore() async {
    mode = ConsoleMode.parse(await _store.read(_key));
    for (final l in List.of(_listeners)) {
      l(mode);
    }
  }

  /// Moves to the next face and remembers it.
  Future<ConsoleMode> cycle() async {
    mode = mode.next;
    for (final l in List.of(_listeners)) {
      l(mode);
    }
    await _store.write(_key, mode.name);
    return mode;
  }
}
