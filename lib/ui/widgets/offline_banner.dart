import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;

/// Thin strip below the app bar when offline or server unreachable.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([services.sync, services.outbox]),
      builder: (context, _) {
        final sync = services.sync;
        if (sync.online && !sync.serverUnreachable) return const SizedBox.shrink();
        final queued = services.outbox.pending;
        if (sync.online) {
          // Signal, but no server: say what is on screen is the phone's copy, and how old.
          final at = sync.servedFromCacheAt;
          return Container(
            key: const Key('offline-banner-unreachable'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: C.amberBg,
            child: Text(
              'Server unreachable · showing what is on this phone'
              '${at == null ? '' : ' · last updated ${fmt.ago(at.toIso8601String())}'}'
              '${queued > 0 ? ' · ${fmt.plural(queued, "change")} queued' : ''}',
              style: T.tiny.copyWith(color: C.amber),
            ),
          );
        }
        return Container(
          key: const Key('offline-banner-offline'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          color: C.amberBg,
          // BI26101519: text only. The app bar's one cloud already shows offline.
          child: Row(
            children: [
              Expanded(
                child: Text(
                  queued > 0
                      ? 'Offline · ${fmt.plural(queued, "change")} queued · will sync to OneDrive on reconnect'
                      : 'Offline · reading your local mirror',
                  style: T.tiny.copyWith(color: C.amber),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
