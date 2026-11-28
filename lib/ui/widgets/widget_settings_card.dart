import 'package:flutter/material.dart';

import '../../services/widget_sync.dart';
import '../../theme.dart';

/// BI26100138: the one widget setting. A widget cannot tell if the screen is locked, so "hide" means always.
class WidgetSettingsCard extends StatelessWidget {
  const WidgetSettingsCard({super.key, this.sync});
  final WidgetSync? sync;

  @override
  Widget build(BuildContext context) {
    final s = sync ?? activeWidgetSync;
    if (s == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
        child: SwitchListTile(
          key: const Key('widget-hide-next'),
          contentPadding: EdgeInsets.zero,
          title: Text('Hide the next item on the home-screen widget', style: T.body2),
          subtitle: Text('The widget then says an item is due without its title. Finance and health tasks never show on it either way.', style: T.tiny),
          value: s.hideNext,
          onChanged: (v) => s.setHideNext(v),
        ),
      ),
    );
  }
}
