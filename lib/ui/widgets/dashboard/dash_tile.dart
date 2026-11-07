import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../common.dart';

/// BI26100127: the frame every dashboard widget sits in: a panel with a small
/// caps label, the body, and an optional "updated n min ago" line. A tile
/// renders from cached data first and never waits on the network, so it has
/// three honest states besides the data: empty, error and the data itself.
class DashTile extends StatelessWidget {
  const DashTile({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
    this.updatedAt,
    this.error,
  });

  final String label;
  final Widget child;

  /// Where the tile leads: the sub-tab that owns its data.
  final VoidCallback? onTap;

  /// When the cached data was fetched; shown as "updated n min ago".
  final DateTime? updatedAt;

  /// Set when the last refresh failed. The cached body still shows beneath.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final stamp = updatedAgo(updatedAt);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: T.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: C.text3,
                ),
            ],
          ),
          const SizedBox(height: 6),
          child,
          if (error != null || stamp != null) ...[
            const SizedBox(height: 6),
            Text(
              error != null ? 'Could not refresh: $error' : stamp!,
              style: T.tiny.copyWith(color: error != null ? C.amber : C.text3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// "updated 4 min ago", or null when there is no timestamp.
String? updatedAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return null;
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inSeconds < 60) return 'updated just now';
  if (d.inMinutes < 60) return 'updated ${d.inMinutes} min ago';
  if (d.inHours < 24) return 'updated ${d.inHours} h ago';
  return 'updated ${d.inDays} d ago';
}

/// Big-number type: Inter in its tabular figures so digits do not jitter.
const kTabular = [FontFeature.tabularFigures()];

/// The body shown when a tile has no data yet.
class DashEmpty extends StatelessWidget {
  const DashEmpty({super.key, this.text = 'No data yet'});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: T.small.copyWith(color: C.text3)),
  );
}
