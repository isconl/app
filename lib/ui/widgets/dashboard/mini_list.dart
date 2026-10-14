import 'package:flutter/material.dart';

import '../../../theme.dart';
import 'dash_tile.dart';

class MiniItem {
  const MiniItem(this.title, this.trailing, {this.onTap});
  final String title;
  final String trailing;
  final VoidCallback? onTap;
}

/// The top few items with a trailing value. Shows at most [max] rows.
class MiniList extends StatelessWidget {
  const MiniList({
    super.key,
    required this.items,
    this.max = 3,
    this.empty = 'Nothing here',
  });
  final List<MiniItem> items;
  final int max;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return DashEmpty(text: empty);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in items.take(max))
          InkWell(
            onTap: i.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      i.title,
                      style: T.small.copyWith(color: C.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    i.trailing,
                    style: T.small.copyWith(
                      color: C.text3,
                      fontFeatures: kTabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
