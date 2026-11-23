import 'package:flutter/material.dart';

import '../../theme.dart';

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
    // BI26112302: OneDrive is a paused, read-only archive since 30 Sep 2026 (vault 0.1.93 copies nothing to it unless
    // VAULT_CONTENT_TRANSPORT=on), so its state is no longer a sync problem worth a banner. The server is the sync
    // target; the offline banner and the outbox already say when changes are waiting for it.
    if (mounted && _message != null) setState(() => _message = null);
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
          // BI26101519: text only; the one cloud in the app bar carries the state.
          Expanded(child: Text(msg, style: T.small.copyWith(color: C.red))),
        ],
      ),
    );
  }
}
