import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../services/apk_link.dart';

/// BI26101514: "Link for another phone". Asks hub for a one-time ticket and shows the link once with a Copy button.
/// The link lives only in the dialog; closing it forgets it.
class ApkLinkButton extends StatelessWidget {
  const ApkLinkButton({super.key, this.issue});

  /// Tests supply the issuer; the app asks hub.
  final Future<ApkLink> Function()? issue;

  Future<void> _go(BuildContext context) async {
    final ask = issue ?? () => issueApkLink(AppScope.of(context).api);
    ApkLink link;
    try {
      link = await ask();
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } on OfflineException {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline.')));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link for another phone'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(link.url, key: const Key('apk-link-url')),
          const SizedBox(height: 8),
          Text('Works once, for ${link.minutes} minutes. It is not saved.'),
        ]),
        actions: [
          TextButton(
            key: const Key('apk-link-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link.url));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: const Key('apk-link'),
        onPressed: () => _go(context),
        icon: const Icon(Icons.link_rounded, size: 16),
        label: const Text('Link for another phone'),
      );
}
