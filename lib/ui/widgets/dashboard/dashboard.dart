/// BI26100127: the shared dashboard kit. Views import this barrel and never
/// `fl_chart` itself, so every chart in the app keeps one look.
library;

export 'bar_strip.dart';
export 'dash_tile.dart';
export 'dashboard_grid.dart';
export 'mini_list.dart';
export 'ring_gauge.dart';
export 'sparkline.dart';
export 'stacked_bars.dart';
export 'stat_tile.dart';
