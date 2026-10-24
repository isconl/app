import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/ui/views/slate.dart';
import 'package:isconl/ui/shell.dart' show viewForNavRoute;

void main() {
  group('BI26092327: Tasks becomes Slate', () {
    test('the old tasks route and the slate route both land in the Slate view', () {
      expect(viewForNavRoute('tasks')!.$1, isA<SlateView>());
      expect(viewForNavRoute('/api/tasks')!.$1, isA<SlateView>());
      expect(viewForNavRoute('slate')!.$1, isA<SlateView>());
      expect(viewForNavRoute('slate')!.$2, 'Slate');
    });

    test('BS26102104: the strip is Overview, Grid and Asks, and defaults to Overview', () {
      expect(SlateTab.values, [SlateTab.overview, SlateTab.grid, SlateTab.asks]);
      expect(SlateView.remembered, SlateTab.overview);
    });
  });
}
