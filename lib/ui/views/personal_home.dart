import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Personal: dashboard landing screen for sovereign ground and life.
/// Links to Finance, Ideas, Journal, and Learning.
class PersonalHomeView extends StatelessWidget {
  const PersonalHomeView({super.key, this.onNavigate});
  final void Function(int subIndex)? onNavigate;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.state,
      builder: (context, data) {
        final state = fmt.m(data);
        final ideasCount = fmt.i(state['ideas_count']);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Personal & Life Ground'),
              _Tile(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Finance',
                subtitle: 'Net worth, cashflows, capital runway, and investments',
                onTap: () => onNavigate?.call(1),
              ),
              const SizedBox(height: 8),
              _Tile(
                icon: Icons.lightbulb_rounded,
                title: 'Ideas',
                subtitle: 'Captured sparks, insights, and concepts pipeline',
                badge: ideasCount > 0 ? '$ideasCount' : null,
                onTap: () => onNavigate?.call(2),
              ),
              const SizedBox(height: 8),
              _Tile(
                icon: Icons.auto_stories_rounded,
                title: 'Journal',
                subtitle: 'Daily reflections, voice entries, and personal records',
                onTap: () => onNavigate?.call(3),
              ),
              const SizedBox(height: 8),
              _Tile(
                icon: Icons.school_rounded,
                title: 'Learning',
                subtitle: 'Campus curriculum modules, reading progress, and tracks',
                onTap: () => onNavigate?.call(4),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(Sz.rMd),
            ),
            child: Icon(icon, color: C.greenBright, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: T.w600(T.body)),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Badge2(badge!, color: C.greenBg, textColor: C.greenBright),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: T.small),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.text3, size: 18),
        ],
      ),
    );
  }
}
