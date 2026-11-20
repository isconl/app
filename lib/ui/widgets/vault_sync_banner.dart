import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;

/// The persistence-layer warning, ported from dashboard/app.js's
/// checkVaultLink() (~line 617): a broken OneDrive link isn't a degraded
/// feature, it's "your work is stranding on this machine until reconnected".
/// Loud on purpose (a banner, not a card buried in a view), gone the moment
/// the link is back. GET /api/vault/sync/status -> {onedrive, status, error}.
class VaultSyncBanner extends StatefulWidget {
  const VaultSyncBanner({super.key});

  @override
  State<VaultSyncBanner> createState() => _VaultSyncBannerState();
}

class _VaultSyncBannerState extends State<VaultSyncBanner> {
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final services = AppScope.of(context);
    if (!services.sync.online) return;
    try {
      final res =
          fmt.m(await services.api.getJson('/api/vault/sync/status', cold: true));
      if (!mounted) return;
      final onedrive = fmt.b(res['onedrive']);
      final status = fmt.s(res['status']);
      String? bad;
      if (!onedrive) {
        bad = 'OneDrive is not connected - nothing is syncing. Your data is '
            'only on this work machine until you reconnect (Settings -> '
            'Microsoft 365).';
      } else if (status == 'offline') {
        final err = fmt.s(res['error']).isEmpty ? 'unreachable' : fmt.s(res['error']);
        bad = 'OneDrive sync is failing ($err) - changes are staying on this '
            'work machine until it recovers.';
      }
      setState(() => _message = bad);
    } catch (_) {
      // Server unreachable - the rest of the UI already surfaces that; this
      // banner just stays quiet rather than adding a second warning for it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = _message;
    if (msg == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: C.redBg,
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 14, color: C.red),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: T.small.copyWith(color: C.red))),
        ],
      ),
    );
  }
}
