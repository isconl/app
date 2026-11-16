import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

/// The three status lines pinned at the bottom of both the mobile
/// [MenuSheet] and the desktop [SidebarRail] - extracted so the two chrome
/// shells can't drift apart on what "online" actually means.
class SystemStatusLines extends StatelessWidget {
  const SystemStatusLines({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([services.sync, services.session]),
      builder: (context, _) {
        final health = services.session.serverHealth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                StatusDot(services.sync.online ? C.green : C.red,
                    glow: services.sync.online, size: 6),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    services.sync.online
                        ? 'Agent Online · Gate Armed'
                        : 'Agent Unreachable · Local Mirror',
                    style: T.monoSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const StatusDot(C.cyan, size: 6),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(services.sync.statusLine,
                      style: T.monoSmall, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            if (health != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const StatusDot(C.text3, size: 6),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'server v${fmt.s(health['version'])} · build ${fmt.s(health['build'])}',
                      style: T.monoSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
