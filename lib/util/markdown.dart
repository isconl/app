import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// How much room the renderer is being given.
///
/// `compact` is the original: markdown inside a card, tuned to take as little
/// vertical space as it can get away with.
///
/// `reading` is for a page whose whole job is to be read - a learning module,
/// an article, a meeting analysis. It is not the compact style with bigger
/// numbers. It drops every box it can: no card, no table outline, no code
/// border, headings that earn their space, and a line height you can follow
/// down a 3,000-word module without losing your place.
enum MarkdownVariant { compact, reading }

/// Compact markdown renderer covering what the agent actually emits:
/// headings, bold/italic, inline + fenced code, lists, blockquotes,
/// horizontal rules, links and tables. No external dependency, fully offline.
class Markdown extends StatelessWidget {
  const Markdown(this.source,
      {super.key,
      this.baseStyle,
      this.variant = MarkdownVariant.compact,
      this.courseId = '',
      this.baseUrl = '',
      this.token = ''});
  final String source;
  final TextStyle? baseStyle;
  final MarkdownVariant variant;
  /// If set, `![alt](_assets/file.ext)` paths resolve to
  /// `$baseUrl/api/learning/asset?course=$courseId&file=file.ext&token=$token`.
  final String courseId;
  final String baseUrl;
  /// The session's bearer token -- Image.network can't send an
  /// Authorization header, so it goes on the URL as a query param instead
  /// (the same fallback hub's checkAuth accepts for any /api/* route).
  final String token;

  bool get _reading => variant == MarkdownVariant.reading;


  @override
  Widget build(BuildContext context) {
    final style = baseStyle ??
        (_reading
            ? T.body.copyWith(
                fontSize: 15.5, height: 1.72, color: C.text, letterSpacing: 0.1)
            : T.body2.copyWith(color: C.text, height: 1.55));
    final blocks = _parseBlocks(source);
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final w = _renderBlock(blocks[i], style, first: i == 0);
      if (w != null) children.add(w);
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget? _renderBlock(_Block block, TextStyle style, {bool first = false}) {
    switch (block.kind) {
      case _Kind.heading:
        final size = _reading
            ? switch (block.level) {
                1 => 22.0,
                2 => 18.5,
                3 => 16.0,
                _ => 14.5,
              }
            : switch (block.level) {
                1 => 17.0,
                2 => 15.5,
                3 => 14.5,
                _ => 13.5,
              };
        // Space above a heading belongs to the heading, not to the paragraph
        // that ended. Suppressed on the very first block so a module does not
        // open with a gap.
        final top = _reading ? (first ? 0.0 : (block.level <= 2 ? 30.0 : 22.0)) : 12.0;
        final bottom = _reading ? (block.level <= 2 ? 10.0 : 7.0) : 4.0;
        return Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: Text.rich(
            _inline(
              block.text,
              style.copyWith(
                fontSize: size,
                height: _reading ? 1.28 : null,
                fontWeight: block.level <= 2 ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: _reading && block.level <= 2 ? -0.4 : null,
              ),
            ),
          ),
        );
      case _Kind.code:
        return Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(vertical: _reading ? 14 : 6),
          padding: EdgeInsets.all(_reading ? 14 : 10),
          decoration: BoxDecoration(
            // Reading mode leans on a tinted fill instead of a border. One
            // fewer line on the page, same separation.
            color: _reading ? C.bgRaised : C.bg,
            border: _reading ? null : Border.all(color: C.border),
            borderRadius: BorderRadius.circular(_reading ? Sz.rMd : Sz.rSm),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              block.text,
              style: T.mono.copyWith(
                  color: C.text2, fontSize: _reading ? 12.5 : null, height: 1.5),
            ),
          ),
        );
      case _Kind.quote:
        return Container(
          margin: EdgeInsets.symmetric(vertical: _reading ? 16 : 6),
          padding: EdgeInsets.only(left: _reading ? 16 : 10),
          decoration: BoxDecoration(
            border: Border(
                left: BorderSide(color: C.green, width: _reading ? 2.5 : 2)),
          ),
          child: Text.rich(_inline(
            block.text,
            _reading
                ? style.copyWith(
                    color: C.text2,
                    fontSize: 15.5,
                    fontStyle: FontStyle.italic,
                    height: 1.68)
                : style.copyWith(color: C.text2),
          )),
        );
      case _Kind.rule:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: _reading ? 22 : 8),
          child: const Divider(),
        );
      case _Kind.listItem:
        final bullet = block.ordered ? '${block.index}.' : '•';
        return Padding(
          padding: EdgeInsets.only(
            left: (_reading ? 2.0 : 4.0) + block.level * (_reading ? 18 : 14),
            top: _reading ? 4 : 2,
            bottom: _reading ? 4 : 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: block.ordered ? (_reading ? 26 : 22) : (_reading ? 18 : 14),
                child: Text(bullet,
                    style: style.copyWith(
                        color: C.green, fontWeight: FontWeight.w600)),
              ),
              Expanded(child: Text.rich(_inline(block.text, style))),
            ],
          ),
        );
      case _Kind.callout:
        return _callout(block, style);
      case _Kind.table:
        return _table(block, style);
      case _Kind.chart:
        return _chart(block);
      case _Kind.map:
        return _map(block);
      case _Kind.equation:
        return _equation(block);
      case _Kind.image:
        return _image(block);
      case _Kind.paragraph:
        if (block.text.trim().isEmpty) return null;
        return Padding(
          padding: EdgeInsets.symmetric(vertical: _reading ? 7 : 3),
          child: Text.rich(_inline(block.text, style)),
        );
    }
  }

  /// One callout: coloured background, left strip line, label above the body.
  ///
  /// Same shape for all five so the eye learns it once; only the colour and the
  /// label change. It is a Container rather than a Card on purpose - a card
  /// would set it apart from the prose, and a callout is part of the reading,
  /// not an aside beside it.
  Widget _callout(_Block block, TextStyle style) {
    final c = block.callout!;
    final pad = _reading ? 14.0 : 10.0;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: _reading ? 14 : 6),
      padding: EdgeInsets.fromLTRB(pad, pad * 0.8, pad, pad * 0.8),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(left: BorderSide(color: c.colour, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(Sz.rMd),
          bottomRight: Radius.circular(Sz.rMd),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.label.toUpperCase(),
            style: T.mono.copyWith(
              fontSize: 9.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
              color: c.colour,
            ),
          ),
          const SizedBox(height: 5),
          Text.rich(_inline(
            block.text,
            style.copyWith(
              color: C.text,
              fontSize: _reading ? 15 : 13,
              height: 1.62,
              fontStyle: c.kind == 'quote' ? FontStyle.italic : null,
            ),
          )),
          if (block.cite.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              block.cite,
              style: T.mono.copyWith(
                fontSize: 10.5, height: 1.5, color: C.text3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _table(_Block block, TextStyle style) {
    final rows = block.rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final cellStyle = style.copyWith(fontSize: _reading ? 13.5 : 12, height: 1.45);
    return Container(
      margin: EdgeInsets.symmetric(vertical: _reading ? 16 : 6),
      decoration: BoxDecoration(
        // Reading mode uses horizontal rules only - the outline and the
        // vertical grid are what make a table read as a widget instead of
        // part of the prose.
        border: _reading ? null : Border.all(color: C.border),
        borderRadius: BorderRadius.circular(Sz.rSm),
      ),
      clipBehavior: _reading ? Clip.none : Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: _reading
              ? const TableBorder(
                  horizontalInside: BorderSide(color: C.border),
                  top: BorderSide(color: C.borderMid),
                  bottom: BorderSide(color: C.border),
                )
              : const TableBorder(
                  horizontalInside: BorderSide(color: C.border),
                  verticalInside: BorderSide(color: C.border),
                ),
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(
                    color: r == 0 && !_reading ? C.surface : null),
                children: [
                  for (final cell in rows[r])
                    Padding(
                      padding: EdgeInsets.only(
                        left: _reading ? 0 : 10,
                        right: _reading ? 20 : 10,
                        top: _reading ? 9 : 6,
                        bottom: _reading ? 9 : 6,
                      ),
                      child: Text.rich(_inline(
                          cell,
                          r == 0
                              ? cellStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: _reading ? C.text3 : null,
                                  letterSpacing: _reading ? 0.4 : null)
                              : cellStyle)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _chart(_Block block) {
    final title = block.chartTitle;
    final items = block.chartItems;
    final maxVal = items.isEmpty ? 1.0 : items.map((e) => e.value.abs()).reduce((a, b) => a > b ? a : b);
    final safeMax = maxVal == 0 ? 1.0 : maxVal;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: _reading ? 16 : 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.bgRaised,
        border: Border.all(color: C.border),
        borderRadius: BorderRadius.circular(Sz.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, size: 16, color: C.cyan),
              const SizedBox(width: 6),
              Text(
                title.isNotEmpty ? title : 'CHART',
                style: T.label.copyWith(color: C.cyan, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(it.label, style: T.body2.copyWith(fontSize: 12.5)),
                      Text('${it.value}', style: T.mono.copyWith(fontSize: 12, color: C.text2)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (it.value.abs() / safeMax).clamp(0.0, 1.0),
                      backgroundColor: C.surface,
                      valueColor: const AlwaysStoppedAnimation<Color>(C.green),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _map(_Block block) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: _reading ? 16 : 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.bgRaised,
        border: Border.all(color: C.border),
        borderRadius: BorderRadius.circular(Sz.rMd),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(Sz.rSm),
            ),
            child: const Icon(Icons.map_rounded, size: 24, color: C.amber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.mapLabel.isNotEmpty ? block.mapLabel : 'Location Map',
                  style: T.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${block.mapLat}, ${block.mapLon} (zoom ${block.mapZoom})',
                  style: T.mono.copyWith(fontSize: 11, color: C.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _equation(_Block block) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: _reading ? 16 : 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.bgRaised,
        border: Border.all(color: C.borderMid),
        borderRadius: BorderRadius.circular(Sz.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EQUATION', style: T.label.copyWith(color: C.violet, fontSize: 9.5)),
          const SizedBox(height: 6),
          Center(
            child: Text(
              block.text,
              style: T.mono.copyWith(fontSize: 14.5, color: C.text, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  // BL26083105: resolve _assets/ path to the hub's /api/learning/asset
  // endpoint. `token` appended as a query param -- Image.network can't
  // send an Authorization header, and this route sits behind the same
  // auth as every other /api/* route (found live 6 Sep 2026: every
  // lesson image was silently 401ing without this).
  String _resolveImageUrl(String raw) {
    if (raw.startsWith('_assets/') && courseId.isNotEmpty && baseUrl.isNotEmpty) {
      final base = baseUrl.trimRight().replaceAll(RegExp(r'/$'), '');
      final file = Uri.encodeComponent(raw.substring(8));
      final cid  = Uri.encodeComponent(courseId);
      final tok  = Uri.encodeComponent(token);
      return '$base/api/learning/asset?course=$cid&file=$file&token=$tok';
    }
    return raw;
  }

  // BL26083105: a missing alt or a hot-linked external URL is a build-time
  // lint, not a silent accept — mirrors learnMd()'s red-flagged inline
  // callout on web (same "cite it or do not claim it" discipline).
  Widget _imageLintBlocked(String message) => Container(
        margin: EdgeInsets.symmetric(vertical: _reading ? 16 : 8),
        child: Text(message, style: T.small.copyWith(color: C.red)),
      );

  Widget _image(_Block block) {
    if (block.imageAlt.trim().isEmpty) {
      return _imageLintBlocked(
          '[Image blocked: missing required alt text — add `![Descriptive alt text](${block.imageUrl})`]');
    }
    final isExternal = RegExp(r'^https?://', caseSensitive: false).hasMatch(block.imageUrl);
    final isAsset = block.imageUrl.startsWith('_assets/');
    if (isExternal && !isAsset) {
      return _imageLintBlocked(
          '[Image blocked: must be stored in _assets/, not linked externally]');
    }
    final resolvedUrl = _resolveImageUrl(block.imageUrl);
    final rawCaption = block.imageCaption.trim();
    // Detect _captured DD Mon YYYY_ pattern (mirrors web renderer's convention)
    final capturedMatch = RegExp(r'_captured\s+([^_]+)_', caseSensitive: false)
        .firstMatch(rawCaption);
    final capturedText = capturedMatch?.group(1)?.trim() ?? '';
    final captionText  = rawCaption
        .replaceAll(RegExp(r'_captured\s+[^_]+_', caseSensitive: false), '')
        .trim();

    Widget imgWidget(BuildContext context) => GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(12),
              child: Stack(children: [
                InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 6.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      resolvedUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported_rounded,
                          color: Colors.white54, size: 48),
                    ),
                  ),
                ),
                Positioned(
                  top: 0, right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ),
              ]),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Sz.rMd),
              border: Border.all(color: C.border),
              boxShadow: const [BoxShadow(color: Color(0x1a000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Sz.rMd),
              child: Image.network(
                resolvedUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: BorderRadius.circular(Sz.rMd),
                    border: Border.all(color: C.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.image_not_supported_rounded, size: 20, color: C.text3),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      captionText.isNotEmpty ? captionText : block.imageUrl,
                      style: T.small.copyWith(color: C.text3),
                    )),
                  ]),
                ),
              ),
            ),
          ),
        );

    return Container(
      margin: EdgeInsets.symmetric(vertical: _reading ? 16 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(builder: imgWidget),
          if (captionText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(captionText, style: T.tiny.copyWith(color: C.text3)),
          ],
          if (capturedText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('captured $capturedText',
                style: T.tiny.copyWith(color: C.text3, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }


  /// Inline markdown: **bold**, *italic*, `code`, [text](url), and (BL26083104)
  /// the `[[term|definition]]` jargon marker -- matched first so its double
  /// brackets are never mistaken for the `[text](url)` link group below,
  /// which requires a `(url)` immediately after `]` a jargon marker never has.
  TextSpan _inline(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    // BL26091115: the jargon marker grew from `[[term|definition]]` to
    // `[[term|definition|etymology|example]]`. Etymology and example are
    // optional, so group 3 stays greedy over the remaining pipes and is split
    // afterwards -- that keeps every existing two-field marker matching
    // exactly as before rather than needing a second pattern.
    final pattern = RegExp(
        r'(\[\[([^|\]]+)\|([^\]]+)\]\])|(\*\*(.+?)\*\*)|(\*([^*]+?)\*)|(_([^_]+?)_)|(`([^`]+?)`)|(\[([^\]]+)\]\(([^)]+)\))');
    var pos = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > pos) {
        spans.add(TextSpan(text: text.substring(pos, match.start)));
      }
      if (match.group(1) != null) {
        final parts = match.group(3)!.split('|');
        spans.add(_jargonTermSpan(
          match.group(2)!.trim(),
          parts[0].trim(),
          style,
          etymology: parts.length > 1 ? parts[1].trim() : null,
          example: parts.length > 2 ? parts[2].trim() : null,
        ));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(
            text: match.group(5),
            style: const TextStyle(fontWeight: FontWeight.w600)));
      } else if (match.group(6) != null) {
        spans.add(TextSpan(
            text: match.group(7),
            style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (match.group(8) != null) {
        spans.add(TextSpan(
            text: match.group(9),
            style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (match.group(10) != null) {
        spans.add(TextSpan(
          text: match.group(11),
          style: T.mono.copyWith(
              color: C.greenBright,
              fontSize: (style.fontSize ?? 13) - 1,
              backgroundColor: C.surface),
        ));
      } else if (match.group(12) != null) {
        final url = match.group(14)!;
        spans.add(TextSpan(
          text: match.group(13),
          style: const TextStyle(
              color: C.cyan, decoration: TextDecoration.underline,
              decorationColor: C.cyan),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ));
      }
      pos = match.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: spans);
  }

  /// BL26083104: a purple, code-styled inline span for a jargon term,
  /// wherever it appears in flowing text -- replaces the old full-width
  /// Jargon callout for new/rewritten content. A `Builder` gets a fresh
  /// `BuildContext` bound right here (rather than threading `context`
  /// through every `_inline` call site above), which is all
  /// `showJargonDefinition` below needs to find the enclosing Navigator.
  WidgetSpan _jargonTermSpan(String term, String definition, TextStyle style,
      {String? etymology, String? example}) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Builder(
        builder: (context) => GestureDetector(
          onTap: () => showJargonDefinition(context, term, definition,
              etymology: etymology, example: example),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: C.violet.withValues(alpha: 0.1),
              border: Border.all(color: C.violet.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              term,
              style: T.mono.copyWith(
                color: C.violet,
                fontSize: (style.fontSize ?? 15.5) - 1,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// BL26083104 / BL26091115: the definition popup for an inline jargon term.
///
/// Was a bottom sheet. Now a centred floating dialog, per Sconl: "no bottom
/// modal on mobile, floating modal, center of the screen." A bottom sheet
/// pushes the reader's eye to the edge of the screen and away from the word
/// they just tapped; a centred card keeps attention where the reading is.
///
/// Etymology and example are optional and simply absent from the card when the
/// marker does not supply them, so every existing two-field
/// `[[term|definition]]` renders exactly as before.
Future<void> showJargonDefinition(
  BuildContext context,
  String term,
  String definition, {
  String? etymology,
  String? example,
}) {
  final copyText = [
    term,
    definition,
    if (etymology != null && etymology.isNotEmpty) 'Origin: $etymology',
    if (example != null && example.isNotEmpty) 'Example: $example',
  ].join('

');

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: C.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sz.rXl),
        side: const BorderSide(color: C.border),
      ),
      child: ConstrainedBox(
        // A definition can run long once etymology and an example are in it.
        // Bounded and scrollable rather than allowed to grow off-screen.
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(term,
                          style: T.title.copyWith(
                              color: C.violet, fontFamily: T.mono.fontFamily)),
                    ),
                    _JargonCopyButton(text: copyText),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: C.text3),
                      onPressed: () => Navigator.of(ctx).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(definition, style: T.body.copyWith(color: C.text, height: 1.5)),
                if (etymology != null && etymology.isNotEmpty)
                  _JargonSection(label: 'Origin', body: etymology),
                if (example != null && example.isNotEmpty)
                  _JargonSection(label: 'In a sentence', body: example, italic: true),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A labelled sub-section of the jargon card. Same shape for origin and
/// example so the eye learns it once.
class _JargonSection extends StatelessWidget {
  const _JargonSection({required this.label, required this.body, this.italic = false});
  final String label;
  final String body;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: T.tiny.copyWith(
                  color: C.text3, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(body,
              style: T.body2.copyWith(
                  color: C.text2,
                  height: 1.5,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
        ],
      ),
    );
  }
}

/// Copy the whole definition to the clipboard, confirming in place rather than
/// with a SnackBar -- the dialog is centred and modal, so a bar at the bottom
/// of the screen is exactly where the reader is not looking.
class _JargonCopyButton extends StatefulWidget {
  const _JargonCopyButton({required this.text});
  final String text;

  @override
  State<_JargonCopyButton> createState() => _JargonCopyButtonState();
}

class _JargonCopyButtonState extends State<_JargonCopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded,
          size: 18, color: _copied ? C.green : C.text3),
      tooltip: _copied ? 'Copied' : 'Copy definition',
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        if (!mounted) return;
        setState(() => _copied = true);
        _reset?.cancel();
        _reset = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _copied = false);
        });
      },
    );
  }
}

enum _Kind { paragraph, heading, code, quote, rule, listItem, table, callout, chart, map, equation, image }

/// The five lesson callouts.
class _Callout {
  const _Callout(this.kind, this.label, this.colour, this.background, this.pattern);
  final String kind;
  final String label;
  final Color colour;
  final Color background;
  final RegExp pattern;
}

final _callouts = <_Callout>[
  _Callout('learn', 'Objective', C.callLearn, C.callLearnBg,
      RegExp(r'^\*\*(?:What you will learn|What will be learnt|You will be able to|Objective|Learning outcomes?):?\*\*\s*',
          caseSensitive: false)),
  _Callout('jargon', 'Jargon', C.callJargon, C.callJargonBg,
      RegExp(r'^\*\*(?:Jargon|In plain language|Plain language|The word):?\*\*\s*',
          caseSensitive: false)),
  _Callout('watch', 'Failure', C.callWatch, C.callWatchBg,
      RegExp(r'^\*\*(?:What to watch for|Watch out for|Watch for|Watch|Failure|Careful):?\*\*\s*',
          caseSensitive: false)),
  _Callout('book', 'Book', C.callBook, C.callBookBg,
      RegExp(r'^\*\*(?:In a book|Book|From the literature):?\*\*\s*',
          caseSensitive: false)),
  _Callout('quote', 'Book quote', C.callQuote, C.callQuoteBg,
      RegExp(r'^\*\*(?:Book quote|Quote|In their words):?\*\*\s*',
          caseSensitive: false)),
  _Callout('research', 'Research', C.callResearch, C.callResearchBg,
      RegExp(r'^\*\*Research:?\*\*\s*', caseSensitive: false)),
  _Callout('fact', 'Fact', C.callFact, C.callFactBg,
      RegExp(r'^\*\*(?:Fun fact|Fact):?\*\*\s*', caseSensitive: false)),
];

_Callout? _matchCallout(String line) {
  for (final c in _callouts) {
    if (c.pattern.hasMatch(line)) return c;
  }
  return null;
}

class _ChartItem {
  const _ChartItem(this.label, this.value);
  final String label;
  final double value;
}

class _Block {
  _Block(this.kind,
      {this.text = '',
      this.level = 0,
      this.ordered = false,
      this.index = 0,
      this.rows = const []});
  final _Kind kind;
  final String text;
  final int level;
  final bool ordered;
  final int index;
  final List<List<String>> rows;

  /// Set only on callout blocks.
  _Callout? callout;
  String cite = '';

  /// Chart / Map / Image / Equation fields
  String chartTitle = '';
  List<_ChartItem> chartItems = const [];
  double mapLat = 0;
  double mapLon = 0;
  int mapZoom = 11;
  String mapLabel = '';
  String imageUrl = '';
  String imageAlt = '';
  String imageCaption = '';
}

List<_Block> _parseBlocks(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_Block>[];
  var idx = 0;
  final para = <String>[];

  void flushPara() {
    if (para.isNotEmpty) {
      blocks.add(_Block(_Kind.paragraph, text: para.join(' ')));
      para.clear();
    }
  }

  while (idx < lines.length) {
    final line = lines[idx];
    final trimmed = line.trimRight();

    // fenced code or media (chart / map)
    if (trimmed.trimLeft().startsWith('```')) {
      flushPara();
      final tag = trimmed.trimLeft().substring(3).trim().toLowerCase();
      final buf = <String>[];
      idx++;
      while (idx < lines.length && !lines[idx].trimLeft().startsWith('```')) {
        buf.add(lines[idx]);
        idx++;
      }
      if (idx < lines.length) idx++; // closing fence

      if (tag == 'chart') {
        final lines = buf;
        var chartTitle = '';
        final items = <_ChartItem>[];
        for (final l in lines) {
          final tMatch = RegExp(r'^title:\s*(.*)$', caseSensitive: false).firstMatch(l);
          if (tMatch != null) { chartTitle = tMatch.group(1)!.trim(); continue; }
          if (RegExp(r'^type:', caseSensitive: false).hasMatch(l)) continue;
          final vMatch = RegExp(r'^([^:]+):\s*(-?\d+(?:\.\d+)?)$').firstMatch(l);
          if (vMatch != null) {
            items.add(_ChartItem(vMatch.group(1)!.trim(), double.tryParse(vMatch.group(2)!) ?? 0));
          }
        }
        blocks.add(_Block(_Kind.chart, text: buf.join('\n'))
          ..chartTitle = chartTitle
          ..chartItems = items);
      } else if (tag == 'map') {
        var lat = 0.0; var lon = 0.0; var zoom = 11; var label = '';
        for (final l in buf) {
          final latM = RegExp(r'^lat:\s*(-?\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(l);
          if (latM != null) { lat = double.tryParse(latM.group(1)!) ?? 0.0; continue; }
          final lonM = RegExp(r'^lon:\s*(-?\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(l);
          if (lonM != null) { lon = double.tryParse(lonM.group(1)!) ?? 0.0; continue; }
          final zoomM = RegExp(r'^zoom:\s*(\d+)', caseSensitive: false).firstMatch(l);
          if (zoomM != null) { zoom = int.tryParse(zoomM.group(1)!) ?? 11; continue; }
          final lblM = RegExp(r'^label:\s*(.*)', caseSensitive: false).firstMatch(l);
          if (lblM != null) { label = lblM.group(1)!.trim(); continue; }
        }
        blocks.add(_Block(_Kind.map, text: buf.join('\n'))
          ..mapLat = lat ..mapLon = lon ..mapZoom = zoom ..mapLabel = label);
      } else {
        blocks.add(_Block(_Kind.code, text: buf.join('\n')));
      }
      continue;
    }

    // Display math equation $$...$$
    if (trimmed.startsWith(r'$$')) {
      flushPara();
      final buf = <String>[];
      if (trimmed.endsWith(r'$$') && trimmed.length > 2) {
        buf.add(trimmed.substring(2, trimmed.length - 2).trim());
        idx++;
      } else {
        buf.add(trimmed.substring(2).trim());
        idx++;
        while (idx < lines.length && !lines[idx].contains(r'$$')) {
          buf.add(lines[idx]);
          idx++;
        }
        if (idx < lines.length) {
          final last = lines[idx];
          final endIdx = last.indexOf(r'$$');
          buf.add(last.substring(0, endIdx));
          idx++;
        }
      }
      blocks.add(_Block(_Kind.equation, text: buf.join('\n').trim()));
      continue;
    }

    // Standalone image ![alt](url "caption") — title-syntax caption mirrors
    // the web renderer's `caption = title || alt` convention (learnMd()).
    final imgMatch = RegExp(r'^!\[([^\]]*)\]\(([^\s)]+)(?:\s+"([^"]*)")?\)$').firstMatch(trimmed);
    if (imgMatch != null) {
      flushPara();
      final alt = imgMatch.group(1)!.trim();
      final title = imgMatch.group(3)?.trim() ?? '';
      blocks.add(_Block(_Kind.image)
        ..imageAlt = alt
        ..imageCaption = title.isNotEmpty ? title : alt
        ..imageUrl = imgMatch.group(2)!.trim());
      idx++;
      continue;
    }

    // table: header row | separator row
    if (trimmed.startsWith('|') &&
        idx + 1 < lines.length &&
        RegExp(r'^\s*\|?[\s:|-]+\|?\s*$').hasMatch(lines[idx + 1]) &&
        lines[idx + 1].contains('-')) {
      flushPara();
      final rows = <List<String>>[_splitRow(trimmed)];
      idx += 2;
      while (idx < lines.length && lines[idx].trimRight().startsWith('|')) {
        rows.add(_splitRow(lines[idx].trimRight()));
        idx++;
      }
      blocks.add(_Block(_Kind.table, rows: rows));
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flushPara();
      blocks.add(_Block(_Kind.heading,
          text: heading.group(2)!, level: heading.group(1)!.length));
      idx++;
      continue;
    }

    if (RegExp(r'^\s*([-*_])\s*\1\s*\1[\s\-*_]*$').hasMatch(trimmed) &&
        trimmed.isNotEmpty) {
      flushPara();
      blocks.add(_Block(_Kind.rule));
      idx++;
      continue;
    }

    // A callout is a single line and claims it before anything else can, because
    // it opens with bold text and would otherwise be swallowed into a paragraph.
    final callout = _matchCallout(trimmed);
    if (callout != null) {
      flushPara();
      var body = trimmed.replaceFirst(callout.pattern, '').trim();
      var cite = '';
      if (callout.kind == 'book' || callout.kind == 'quote') {
        // A trailing [Author, Title, Year, chapter] is the part that makes a
        // book callout checkable rather than decorative, so it gets its own line.
        final m = RegExp(r'\[([^\]]{4,})\]\s*$').firstMatch(body);
        if (m != null) {
          cite = m.group(1)!;
          body = body.substring(0, m.start).trim();
        }
      }
      blocks.add(_Block(_Kind.callout, text: body)
        ..callout = callout
        ..cite = cite);
      idx++;
      continue;
    }

    if (trimmed.startsWith('>')) {
      flushPara();
      final buf = <String>[trimmed.replaceFirst(RegExp(r'^>\s?'), '')];
      idx++;
      while (idx < lines.length && lines[idx].trimRight().startsWith('>')) {
        buf.add(lines[idx].trimRight().replaceFirst(RegExp(r'^>\s?'), ''));
        idx++;
      }
      blocks.add(_Block(_Kind.quote, text: buf.join(' ')));
      continue;
    }

    final unordered = RegExp(r'^(\s*)[-*+]\s+(.*)$').firstMatch(line);
    if (unordered != null) {
      flushPara();
      blocks.add(_Block(_Kind.listItem,
          text: unordered.group(2)!,
          level: (unordered.group(1)!.length / 2).floor()));
      idx++;
      continue;
    }

    final ordered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$').firstMatch(line);
    if (ordered != null) {
      flushPara();
      blocks.add(_Block(_Kind.listItem,
          text: ordered.group(3)!,
          ordered: true,
          index: int.tryParse(ordered.group(2)!) ?? 1,
          level: (ordered.group(1)!.length / 2).floor()));
      idx++;
      continue;
    }

    if (trimmed.isEmpty) {
      flushPara();
      idx++;
      continue;
    }

    para.add(trimmed);
    idx++;
  }
  flushPara();
  return blocks;
}

List<String> _splitRow(String row) {
  var body = row.trim();
  if (body.startsWith('|')) body = body.substring(1);
  if (body.endsWith('|')) body = body.substring(0, body.length - 1);
  return body.split('|').map((c) => c.trim()).toList();
}
