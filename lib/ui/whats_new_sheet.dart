import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../services/whats_new.dart';
import '../theme.dart';

/// Shows the "What's new" sheet once after an update, from the notes bundled in the build (BI26101213, on
/// BI26100531's sheet). Never blocks startup: every failure path returns quietly, and a fresh install or a
/// release with no notes shows nothing.
Future<void> maybeShowWhatsNew(BuildContext context, {WhatsNew? service}) async {
  try {
    final installed = AppScope.of(context).updater.installedVersion;
    final wn = service ?? WhatsNew.bundled();
    final notes = await wn.pending(installed);
    if (notes == null || !context.mounted) return;
    await wn.markShown(installed);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      builder: (_) => WhatsNewSheet(notes: notes),
    );
  } catch (_) {
    // A release-notes sheet is never worth a crash or a delayed start.
  }
}

class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key, required this.notes});

  final WhatsNewNotes notes;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notes.heading, style: T.headline, key: const Key('whats-new-title')),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final g in notes.groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(g.label, style: T.title, key: Key('whats-new-group-${g.label}')),
                        ),
                        for (final line in g.items)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  ', style: TextStyle(color: C.text3)),
                                Expanded(child: Text(line, style: T.body2)),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('whats-new-close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
