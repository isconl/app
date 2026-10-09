import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../services/whats_new.dart';
import '../theme.dart';

/// Shows "What's new in <version>" once after an update (BI26100531). Never blocks startup: every failure
/// path returns quietly, and a fresh install or an empty release body shows nothing.
Future<void> maybeShowWhatsNew(BuildContext context, {WhatsNew? service}) async {
  try {
    final services = AppScope.of(context);
    final installed = services.updater.installedVersion;
    final wn = service ?? WhatsNew.forApi(() => services.session.api);
    final notes = await wn.pending(installed);
    if (notes == null || !context.mounted) return;
    await wn.markShown(installed);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      builder: (_) => WhatsNewSheet(version: installed, notes: notes),
    );
  } catch (_) {
    // A release-notes sheet is never worth a crash or a delayed start.
  }
}

class WhatsNewSheet extends StatefulWidget {
  const WhatsNewSheet({super.key, required this.version, required this.notes});

  final String version;
  final String notes;

  @override
  State<WhatsNewSheet> createState() => _WhatsNewSheetState();
}

class _WhatsNewSheetState extends State<WhatsNewSheet> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// Inline `[text](https://...)` links become tappable text that opens outside the app; any other URL
  /// scheme is shown as plain text and does nothing.
  TextSpan _inline(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)').allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final uri = Uri.tryParse(m.group(2)!);
      final web = uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
      if (web) {
        final rec = TapGestureRecognizer()..onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication);
        _recognizers.add(rec);
        spans.add(TextSpan(text: m.group(1), style: const TextStyle(color: C.cyan, decoration: TextDecoration.underline), recognizer: rec));
      } else {
        spans.add(TextSpan(text: m.group(1)));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: style, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    _recognizers.clear();
    final lines = parseNotes(widget.notes);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("What's new in ${widget.version}", style: T.headline, key: const Key('whats-new-title')),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in lines)
                        Padding(
                          padding: EdgeInsets.only(top: l.kind == 'heading' ? 10 : 4),
                          child: switch (l.kind) {
                            'heading' => Text(l.text, style: T.title),
                            'bullet' => Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('•  ', style: TextStyle(color: C.text3)),
                                  Expanded(child: Text.rich(_inline(l.text, T.body2))),
                                ],
                              ),
                            _ => Text.rich(_inline(l.text, T.body2)),
                          },
                        ),
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
