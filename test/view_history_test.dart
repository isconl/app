import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/view_history.dart';

void main() {
  test('back and forward walk the opened views, and opening drops what was ahead', () {
    final h = ViewHistory('hub');
    expect(h.canBack, isFalse);
    expect(h.open('inbox'), isTrue);
    expect(h.open('tasks'), isTrue);
    expect(h.back(), 'inbox');
    expect(h.back(), 'hub');
    expect(h.back(), isNull, reason: 'nothing before the first view');
    expect(h.forward(), 'inbox');
    expect(h.open('study'), isTrue);
    expect(h.forward(), isNull, reason: 'tasks was dropped when study opened');
    expect(h.current, 'study');
  });

  test('the same view twice in a row is one entry', () {
    final h = ViewHistory('hub');
    expect(h.open('hub'), isFalse);
    h.open('inbox');
    expect(h.open('inbox'), isFalse);
    expect(h.back(), 'hub');
  });

  test('the history is capped so a long session cannot grow it without end', () {
    final h = ViewHistory('v0');
    for (var i = 1; i <= ViewHistory.cap + 20; i++) {
      h.open('v$i');
    }
    var steps = 0;
    while (h.back() != null) {
      steps++;
    }
    expect(steps, ViewHistory.cap - 1);
  });

  test('a web fragment names a view only when it is a plain id', () {
    expect(viewFromFragment('/inbox'), 'inbox');
    expect(viewFromFragment('study_plan'), 'study_plan');
    expect(viewFromFragment(''), isNull);
    expect(viewFromFragment('/'), isNull);
    expect(viewFromFragment('/inbox?x=1'), isNull);
    expect(viewFromFragment('/<script>'), isNull);
    expect(viewFromFragment('/${'a' * 41}'), isNull);
  });
}
