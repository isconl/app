import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'reader_prefs.dart';

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
/// BI26101214: lets the reader act on a paragraph: a long-press calls [onLongPress] with the
/// paragraph's block index and text, and [footer] draws something under it (the tutor's answer).
/// A heading's text as a lowercase, hyphen-joined slug (letters and digits only), the same rule spark uses for the
/// section a recall question came from.
String headingSlug(String text) => text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-').replaceAll(RegExp(r'^-+|-+$'), '');

class ParagraphHook {
  const ParagraphHook({required this.onLongPress, required this.footer});
  final void Function(int index, String text) onLongPress;
  final Widget Function(int index, String text) footer;
}

class Markdown extends StatelessWidget {
  const Markdown(this.source,
      {super.key,
      this.paragraphHook,
      this.anchors,
      this.baseStyle,
      this.variant = MarkdownVariant.compact,
      this.courseId = '',
      this.baseUrl = '',
      this.token = '',
      this.imageSizes = const {},
      this.onModuleLink});
  final String source;

  /// Long-press and footer for paragraphs; null leaves paragraphs as they were.
  final ParagraphHook? paragraphHook;

  /// BI26100537: a `[[link:text|module:<course>/<NN>#anchor]]` was tapped. Null leaves the link inert.
  final void Function(ModuleLink link)? onModuleLink;

  /// BI26100325: when given, every rendered block gets a key so the reader can
  /// save and restore "where I stopped" by block rather than by pixels.
  final MarkdownAnchors? anchors;
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

  /// BI26101106: the pixel size of each `_assets/` file by file name, from the asset manifest, so an
  /// image's room is reserved before it loads. A file with no entry gets a 16:10 placeholder.
  final Map<String, Size> imageSizes;

  bool get _reading => variant == MarkdownVariant.reading;


  @override
  Widget build(BuildContext context) {
    final style = baseStyle ??
        (_reading
            ? T.body.copyWith(
                fontSize: 15.5, height: 1.72 + ReaderPrefs.instance.lineBoost, color: C.text, letterSpacing: 0.1)
            : T.body2.copyWith(color: C.text, height: 1.55));
    final blocks = _parseBlocks(source);
    final figures = _figuresOf(blocks);
    final children = <Widget>[];
    final movements = <String>[];
    final words = <int>[];
    final anchorIndex = <String, int>{};
    var movement = '';
    for (var i = 0; i < blocks.length; i++) {
      var w = _renderBlock(blocks[i], style,
          first: i == 0, lead: i > 0 && blocks[i - 1].kind == _Kind.heading, figures: figures);
      if (w == null) continue;
      final b = blocks[i];
      // BI26101804: a probe followed by its answer is one unit: the probe, then a Reveal answer button that opens the
      // answer in place. The answer is never drawn as a second callout.
      if (b.kind == _Kind.callout && b.callout?.kind == 'probe' && i + 1 < blocks.length &&
          blocks[i + 1].kind == _Kind.callout && blocks[i + 1].callout?.kind == 'answer') {
        w = _RevealAnswer(probe: w, answer: _callout(blocks[i + 1], style));
        i++;
      }
      final hook = paragraphHook;
      if (hook != null && b.kind == _Kind.paragraph) {
        final at = i;
        w = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: () => hook.onLongPress(at, b.text),
            child: w,
          ),
          hook.footer(at, b.text),
        ]);
      }
      if (b.kind == _Kind.heading && b.level <= 2) movement = b.text.trim();
      movements.add(movement);
      words.add(RegExp(r'\S+').allMatches(b.text.isNotEmpty ? b.text : b.quizBody).length);
      if (b.anchor.isNotEmpty) anchorIndex[b.anchor] = children.length;
      // BI26101109: a heading is also reachable by its text slug, which is how a recall question names its section.
      if (b.kind == _Kind.heading) anchorIndex.putIfAbsent(headingSlug(b.text), () => children.length);
      final at = children.length;
      children.add(anchors == null
          ? w
          : KeyedSubtree(
              key: anchors!.keyFor(at),
              child: ValueListenableBuilder<int?>(
                valueListenable: anchors!.highlighted,
                builder: (_, hot, child) => hot == at
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                            color: C.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(Sz.rSm)),
                        child: child)
                    : child!,
                child: w,
              )));
    }
    anchors?._describe(movements, words, anchorIndex);
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget? _renderBlock(_Block block, TextStyle style, {bool first = false, bool lead = false, List<_Figure> figures = const []}) {
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
        final headingText = Text.rich(
          _inline(
            block.text,
            style.copyWith(
              fontSize: size,
              height: _reading ? 1.28 : null,
              fontWeight: block.level <= 2 ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: _reading && block.level <= 2 ? -0.4 : null,
            ),
          ),
        );
        // BI26101106: a heading shows the authored text only. The two-word label is gone; the
        // computed number stays as a small muted mark.
        final eyebrow = block.number;
        return Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: eyebrow.isEmpty
              ? headingText
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow,
                        key: const Key('movement-eyebrow'),
                        style: T.mono.copyWith(fontSize: 11, letterSpacing: 0.6, color: C.text3)),
                    const SizedBox(height: 3),
                    headingText,
                  ],
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
                    height: 1.68 + ReaderPrefs.instance.lineBoost)
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
        if (block.zeroRole == 'prerequisite') return _prerequisite(block, style);
        if (block.zeroRole == 'aside') return _aside(block);
        if (block.zeroRole == 'line') return _quietLine(block, style);
        if (block.zeroRole == 'rung') return _rung(block, style);
        if (block.callout?.kind == 'answer') return _RevealAnswer(answer: _callout(block, style));
        return block.demoted ? _prose(block, style) : _callout(block, style, prominent: block.zeroRole == 'objective');
      case _Kind.quiz:
        return _quizCallout(block, style);
      case _Kind.table:
        return _table(block, style);
      case _Kind.chart:
        return _chart(block);
      case _Kind.map:
        return _map(block);
      case _Kind.equation:
        return _equation(block);
      case _Kind.image:
        return _image(block, figures);
      case _Kind.paragraph:
        if (block.text.trim().isEmpty) return null;
        if (block.zeroRole == 'prerequisite') return _prerequisite(block, style);
        if (block.zeroRole == 'aside') return _aside(block);
        return _paragraph(block.text, style, lead: lead);
    }
  }

  /// BI26101106: reading prose is 16.5 px at 1.65, about 65 characters wide, with 0.9 em between
  /// paragraphs. The first paragraph after a heading is a little larger.
  Widget _paragraph(String text, TextStyle style, {bool lead = false, String cite = ''}) {
    if (!_reading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(_inline(text, style)),
          if (cite.isNotEmpty) _citeLine(cite),
        ]),
      );
    }
    final size = lead ? 17.5 : 16.5;
    final body = style.copyWith(
      fontSize: size,
      height: 1.65 + ReaderPrefs.instance.lineBoost,
      letterSpacing: 0,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: size * 0.45),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(_inline(text, body)),
          if (cite.isNotEmpty) _citeLine(cite),
        ]),
      ),
    );
  }

  /// A Book or Research citation: a muted italic line under its paragraph.
  Widget _citeLine(String cite) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(cite,
            key: const Key('prose-cite'),
            style: T.small.copyWith(color: C.text3, fontStyle: FontStyle.italic, height: 1.45)),
      );

  /// A callout the section rule demoted: its label is dropped and its inline marks are kept.
  Widget _prose(_Block block, TextStyle style) =>
      _paragraph(block.text, style, cite: block.cite);

  /// BI26101804: the prerequisite is a plain italic line with a bold-italic label, no box.
  Widget _prerequisite(_Block block, TextStyle style) {
    final body = style.copyWith(
      color: C.text2,
      fontStyle: FontStyle.italic,
      fontSize: _reading ? 15 : 13,
      height: 1.6 + (_reading ? ReaderPrefs.instance.lineBoost : 0),
    );
    return Padding(
      key: const Key('prerequisite-line'),
      padding: EdgeInsets.symmetric(vertical: _reading ? 8 : 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: 'Prerequisite  ', style: body.copyWith(fontWeight: FontWeight.w700)),
        _inline(block.text, body),
      ])),
    );
  }

  /// BI26101804: "Where this fits" is a small grey aside, no box.
  Widget _aside(_Block block) {
    final small = T.tiny.copyWith(color: C.text3, height: 1.5);
    return Padding(
      key: const Key('where-this-fits'),
      padding: EdgeInsets.symmetric(vertical: _reading ? 6 : 3),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: 'Where this fits  ', style: small.copyWith(fontWeight: FontWeight.w600)),
        _inline(block.text, small),
      ])),
    );
  }

  /// BI26102804: a line element (prior, place, point, link, proof, return, rescore, jargon or book in line form):
  /// its two-word label in small caps, then the text, one step below body in the secondary colour. No box.
  Widget _quietLine(_Block block, TextStyle style) {
    final small = style.copyWith(color: C.text2, fontSize: (style.fontSize ?? 15.5) - 1.5, height: 1.55);
    return Padding(
      key: ValueKey('quiet-line:${block.anchor.isNotEmpty ? block.anchor : identityHashCode(block)}'),
      padding: EdgeInsets.symmetric(vertical: _reading ? 6 : 3),
      child: Text.rich(TextSpan(children: [
        if (block.uiLabel.isNotEmpty)
          TextSpan(
              text: '${block.uiLabel.toUpperCase()}  ',
              style: small.copyWith(fontSize: (small.fontSize ?? 14) - 3, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: C.text3)),
        _inline(block.text, small),
        if (block.cite.isNotEmpty) TextSpan(text: '  ${block.cite}', style: small.copyWith(fontStyle: FontStyle.italic, color: C.text3)),
      ])),
    );
  }

  /// BI26102804: an APPLY rung (now, week, role): its number, the label in bold, then the body; the rungs of a
  /// movement are numbered in order so the three read as one sequence.
  Widget _rung(_Block block, TextStyle style) {
    return Padding(
      key: ValueKey('rung-${block.rungIndex}:${block.anchor.isNotEmpty ? block.anchor : identityHashCode(block)}'),
      padding: EdgeInsets.symmetric(vertical: _reading ? 6 : 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(right: 12, top: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.callLearn, width: 1.5)),
          child: Text('${block.rungIndex}', style: style.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: C.callLearn, height: 1)),
        ),
        Expanded(
          child: Text.rich(TextSpan(children: [
            if (block.uiLabel.isNotEmpty) TextSpan(text: '${block.uiLabel}  ', style: style.copyWith(fontWeight: FontWeight.w700)),
            _inline(block.text, style),
          ])),
        ),
      ]),
    );
  }

  /// One callout: coloured background, left strip line, label above the body.
  ///
  /// Same shape for all five so the eye learns it once; only the colour and the
  /// label change. It is a Container rather than a Card on purpose - a card
  /// would set it apart from the prose, and a callout is part of the reading,
  /// not an aside beside it.
  Widget _callout(_Block block, TextStyle style, {bool prominent = false}) {
    final c = block.callout!;
    final pad = (_reading ? 14.0 : 10.0) + (prominent ? 3 : 0);
    return Container(
      key: prominent ? const Key('objective-callout') : null,
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: _reading ? 14 : 6),
      padding: EdgeInsets.fromLTRB(pad, pad * 0.8, pad, pad * 0.8),
      decoration: BoxDecoration(
        // BI26101804: the objective is the most prominent callout: a stronger fill and a thicker strip.
        color: prominent ? Color.alphaBlend(c.colour.withValues(alpha: 0.12), c.background) : c.background,
        border: Border(left: BorderSide(color: c.colour, width: prominent ? 5 : 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(Sz.rMd),
          bottomRight: Radius.circular(Sz.rMd),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // BI26101106: the authored two-word label is hidden; the callout carries its number and
            // the standard name of its kind.
            [block.number, c.label.toUpperCase()]
                .where((s) => s.isNotEmpty)
                .join('  '),
            key: const Key('callout-label'),
            style: T.mono.copyWith(
              fontSize: prominent ? 11 : 9.5,
              letterSpacing: 1.1,
              fontWeight: prominent ? FontWeight.w700 : FontWeight.w600,
              color: c.colour,
            ),
          ),
          const SizedBox(height: 5),
          Text.rich(_inline(
            block.text,
            style.copyWith(
              color: C.text,
              fontSize: (_reading ? 15 : 13) + (prominent ? 1.5 : 0),
              height: 1.62 + (_reading ? ReaderPrefs.instance.lineBoost : 0),
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

  /// `## Check yourself` / `## Open questions` (BL26091008/FN26091027):
  /// checkmark-accented callout whose answer content is hidden until
  /// revealed. Mirrors web's `.lesson-quiz` (checkmark `::before`,
  /// `counter(quiz-q)` numbering, `.quiz-reveal-btn`) via `_QuizReveal`.
  Widget _quizCallout(_Block block, TextStyle style) {
    final sub = _parseBlocks(block.quizBody);
    final children = <Widget>[];
    var qNum = 0;
    for (final b in sub) {
      if (b.kind == _Kind.listItem) {
        qNum++;
        children.add(_quizListItem(b, style, qNum));
        continue;
      }
      final w = _renderBlock(b, style);
      if (w != null) children.add(w);
    }
    return _QuizReveal(
      title: block.text,
      reading: _reading,
      children: children,
    );
  }

  /// A quiz's list item ignores its source ordered/bullet marker and uses a
  /// running counter instead -- mirrors web's `counter(quiz-q)`, which
  /// numbers every `.md-li` inside `.lesson-quiz` regardless of how the
  /// source marked it up.
  Widget _quizListItem(_Block block, TextStyle style, int number) {
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
            width: _reading ? 22 : 18,
            child: Text('$number.',
                style: style.copyWith(
                    color: C.callQuiz, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text.rich(_inline(block.text, style))),
        ],
      ),
    );
  }

  Widget _table(_Block block, TextStyle style) {
    final rows = block.rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final cellStyle = style.copyWith(fontSize: _reading ? 13.5 : 12, height: 1.45 + (_reading ? ReaderPrefs.instance.lineBoost : 0));
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
              Expanded(
                child: Text(
                  title.isNotEmpty ? title : 'CHART',
                  style: T.label.copyWith(color: C.cyan, fontSize: 11),
                ),
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
                      Expanded(child: Text(it.label, style: T.body2.copyWith(fontSize: 12.5))),
                      const SizedBox(width: 8),
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

  /// Every valid figure of the module, in reading order, for the swipe viewer.
  List<_Figure> _figuresOf(List<_Block> blocks) => [
        for (final b in blocks)
          if (b.kind == _Kind.image && _imageProblem(b) == null) _figure(b),
      ];

  String? _imageProblem(_Block block) {
    if (block.imageAlt.trim().isEmpty) {
      return '[Image blocked: missing required alt text; add `![Descriptive alt text](${block.imageUrl})`]';
    }
    final isExternal = RegExp(r'^https?://', caseSensitive: false).hasMatch(block.imageUrl);
    if (isExternal && !block.imageUrl.startsWith('_assets/')) {
      return '[Image blocked: must be stored in _assets/, not linked externally]';
    }
    return null;
  }

  /// A caption's `_captured DD Mon YYYY_` stamp and its trailing credit (`Credit:`, `Photo:`, `Image:`
  /// or `Source:`, bare or in brackets) are pulled out of the caption text.
  _Figure _figure(_Block block) {
    var caption = block.imageCaption.trim();
    final captured = RegExp(r'_captured\s+([^_]+)_', caseSensitive: false).firstMatch(caption);
    caption = caption.replaceAll(RegExp(r'_captured\s+[^_]+_', caseSensitive: false), '').trim();
    var credit = '';
    final cm = RegExp(r'[\s·|—-]*[(\[]?\b(?:credit|photo|image|source)\s*:\s*([^)\]]+?)[)\]]?\s*$',
            caseSensitive: false)
        .firstMatch(caption);
    if (cm != null) {
      credit = cm.group(1)!.trim();
      caption = caption.substring(0, cm.start).trim();
    }
    final file = block.imageUrl.startsWith('_assets/') ? block.imageUrl.substring(8) : block.imageUrl;
    final size = imageSizes[file];
    return _Figure(
      url: _resolveImageUrl(block.imageUrl),
      cacheKey: courseId.isNotEmpty && block.imageUrl.startsWith('_assets/')
          ? 'asset:$courseId/$file'
          : block.imageUrl,
      path: block.imageUrl,
      caption: caption,
      credit: credit,
      captured: captured?.group(1)?.trim() ?? '',
      ratio: size != null && size.width > 0 && size.height > 0 ? size.width / size.height : 16 / 10,
    );
  }

  Widget _imageBroken(_Figure f, String fallback) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(Sz.rMd),
          border: Border.all(color: C.border),
        ),
        child: Row(children: [
          const Icon(Icons.image_not_supported_rounded, size: 20, color: C.text3),
          const SizedBox(width: 8),
          Expanded(child: Text(f.caption.isNotEmpty ? f.caption : fallback,
              style: T.small.copyWith(color: C.text3))),
        ]),
      );

  /// BI26101106: the room is reserved first (the manifest ratio, or 16:10) behind a soft
  /// placeholder, so text never jumps; the picture is cached on the device by asset path, never by
  /// the URL with its token, so the module reads offline. Caption, then a small muted credit line.
  Widget _image(_Block block, List<_Figure> figures) {
    final problem = _imageProblem(block);
    if (problem != null) return _imageLintBlocked(problem);
    final f = _figure(block);
    final at = figures.indexWhere((x) => x.path == f.path && x.caption == f.caption);

    Widget picture() => ClipRRect(
          borderRadius: BorderRadius.circular(Sz.rMd),
          child: AspectRatio(
            aspectRatio: f.ratio,
            child: CachedNetworkImage(
              key: const Key('module-image'),
              imageUrl: f.url,
              cacheKey: f.cacheKey,
              fit: BoxFit.contain,
              placeholder: (_, _) => const ColoredBox(key: Key('image-placeholder'), color: C.surface),
              errorWidget: (_, _, _) => _imageBroken(f, block.imageUrl),
            ),
          ),
        );

    return Container(
      margin: EdgeInsets.symmetric(vertical: _reading ? 16 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(
            builder: (context) => GestureDetector(
              onTap: () => _showFigures(context, figures.isEmpty ? [f] : figures, at < 0 ? 0 : at),
              child: picture(),
            ),
          ),
          if (f.caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(f.caption, style: T.tiny.copyWith(color: C.text2)),
          ],
          if (f.credit.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(f.credit,
                key: const Key('image-credit'),
                style: T.tiny.copyWith(color: C.text3, fontSize: 10.5)),
          ],
          if (f.captured.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('captured ${f.captured}',
                style: T.tiny.copyWith(color: C.text3, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  /// The full-screen viewer: swipe between all of the module's figures, pinch to zoom each, a close
  /// button, the caption overlaid at the foot.
  static void _showFigures(BuildContext context, List<_Figure> figures, int initial) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _FigureViewer(figures: figures, initial: initial),
    );
  }

  /// Inline markdown: **bold**, *italic*, `code`, [text](url), (BL26083104)
  /// the `[[term|definition]]` jargon marker, and (BI26091928)
  /// `[[link:text|https://...]]` -- the link-marker alternative is matched
  /// FIRST, ahead of the jargon marker, or its `|` makes it match jargon
  /// instead: course-standards.md §8.2 (v3.0.0) distinguishes the two by
  /// rendering (a jargon marker opens a popup in place; a link marker opens
  /// externally, matching the same `[text](url)` link style below), and
  /// this was the one live gap -- `structural-leverage` module 07 rendered
  /// its `[[link:...]]` as a jargon popup showing a bare URL until this fix.
  TextSpan _inline(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    // BL26091115: the jargon marker grew from `[[term|definition]]` to
    // `[[term|definition|etymology|example]]`. Etymology and example are
    // optional, so group 6 stays greedy over the remaining pipes and is split
    // afterwards -- that keeps every existing two-field marker matching
    // exactly as before rather than needing a second pattern.
    final pattern = RegExp(
        r'(\[\[link:([^|\]]+)\|((?:https?://|module:)[^\]]+)\]\])|(\[\[([^|\]]+)\|([^\]]+)\]\])|(\*\*(.+?)\*\*)|(\*([^*]+?)\*)|(_([^_]+?)_)|(`([^`]+?)`)|(\[([^\]]+)\]\(([^)]+)\))|(\[\[([^|\]:]+)\]\])',
        caseSensitive: false);
    var pos = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > pos) {
        spans.add(TextSpan(text: text.substring(pos, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(_externalLinkSpan(match.group(2)!.trim(), match.group(3)!));
      } else if (match.group(4) != null) {
        final parts = match.group(6)!.split('|');
        spans.add(_jargonTermSpan(
          match.group(5)!.trim(),
          parts[0].trim(),
          style,
          etymology: parts.length > 1 ? parts[1].trim() : null,
          example: parts.length > 2 ? parts[2].trim() : null,
        ));
      } else if (match.group(7) != null) {
        // A glossary marker inside bold must still resolve, not show raw `[[`.
        final inner = match.group(8)!;
        spans.add(inner.contains('[[')
            ? TextSpan(
                style: const TextStyle(fontWeight: FontWeight.w600),
                children: [_inline(inner, style)])
            : TextSpan(
                text: inner,
                style: const TextStyle(fontWeight: FontWeight.w600)));
      } else if (match.group(9) != null) {
        spans.add(TextSpan(
            text: match.group(10),
            style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (match.group(11) != null) {
        spans.add(TextSpan(
            text: match.group(12),
            style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (match.group(13) != null) {
        spans.add(TextSpan(
          text: match.group(14),
          style: T.mono.copyWith(
              color: C.greenBright,
              fontSize: (style.fontSize ?? 13) - 1,
              backgroundColor: C.surface),
        ));
      } else if (match.group(15) != null) {
        spans.add(_externalLinkSpan(match.group(16)!, match.group(17)!));
      } else if (match.group(18) != null) {
        // §12.1 bare `[[term]]`: the app has no glossary lookup, so it
        // degrades to the plain term (the standard's own fallback).
        spans.add(TextSpan(
            text: match.group(19)!.trim(),
            style: TextStyle(color: C.violet, fontWeight: FontWeight.w500)));
      }
      pos = match.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: spans);
  }

  /// Shared by both external-link forms -- `[text](url)` and (BI26091928)
  /// `[[link:text|url]]` -- so the two markers stay visually and
  /// behaviourally identical rather than drifting into two different link
  /// styles by accident. Same `TextSpan` + `TapGestureRecognizer` shape the
  /// existing `[text](url)` handling already used before this row, kept
  /// unchanged rather than rebuilt around a `WidgetSpan` -- there is no
  /// context-dependent popup here the way the jargon span needs, so the
  /// simpler mechanism that was already working is the right one to reuse.
  TextSpan _externalLinkSpan(String text, String url) => TextSpan(
        text: text,
        style: const TextStyle(
            color: C.cyan,
            decoration: TextDecoration.underline,
            decorationColor: C.cyan),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            // BI26100537: `module:<course>/<NN>#anchor` opens that exact module and section.
            final module = ModuleLink.parse(url);
            if (module != null) {
              onModuleLink?.call(module);
              return;
            }
            final uri = Uri.tryParse(url);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
      );

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
  ].join('\n\n');

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

/// BL26091008/FN26091027: the answer body of a `## Check yourself` /
/// `## Open questions` block, collapsed by default -- mirrors web's
/// `toggleQuizReveal()` (a `.quiz-body.hidden` class toggle). Header is a
/// checkmark-in-circle + title + a Reveal/Hide toggle; the body only renders
/// once revealed.
/// BI26101804: the answer to a probe, behind a Reveal answer button styled like the notes Write button. It expands in
/// place and folds again on a second tap.
class _RevealAnswer extends StatefulWidget {
  const _RevealAnswer({this.probe, required this.answer});
  final Widget? probe;
  final Widget answer;

  @override
  State<_RevealAnswer> createState() => _RevealAnswerState();
}

class _RevealAnswerState extends State<_RevealAnswer> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.probe != null) widget.probe!,
        InkWell(
          key: const Key('reveal-answer'),
          borderRadius: BorderRadius.circular(Sz.rSm),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_open ? 'Hide answer' : 'Reveal answer', style: T.tiny.copyWith(color: C.green)),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: C.green),
              ],
            ),
          ),
        ),
        if (_open) widget.answer,
      ],
    );
  }
}

class _QuizReveal extends StatefulWidget {
  const _QuizReveal(
      {required this.title, required this.reading, required this.children});
  final String title;
  final bool reading;
  final List<Widget> children;

  @override
  State<_QuizReveal> createState() => _QuizRevealState();
}

class _QuizRevealState extends State<_QuizReveal> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final pad = widget.reading ? 14.0 : 10.0;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: widget.reading ? 14 : 6),
      padding: EdgeInsets.fromLTRB(pad, pad * 0.8, pad, pad * 0.8),
      decoration: BoxDecoration(
        color: C.callQuizBg,
        border: const Border(left: BorderSide(color: C.callQuiz, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(Sz.rMd),
          bottomRight: Radius.circular(Sz.rMd),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: C.callQuiz,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, size: 11, color: C.bgRaised),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.title.toUpperCase(),
                  style: T.mono.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600,
                    color: C.callQuiz,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: C.callQuiz,
                ),
                onPressed: () => setState(() => _revealed = !_revealed),
                child: Text(_revealed ? 'Hide' : 'Reveal',
                    style: T.mono.copyWith(fontSize: 9.5, color: C.callQuiz)),
              ),
            ],
          ),
          if (_revealed) ...[
            const SizedBox(height: 5),
            ...widget.children,
          ],
        ],
      ),
    );
  }
}

/// Where the reader is, by block (BI26100325). A block is one rendered child of
/// a module (heading, paragraph, callout, table...), so a saved position
/// survives a font-size change or a renderer update: re-open the same block, and
/// fall back to the movement or the top when the block no longer exists.
/// BI26100537: a link to a module, and optionally to one section of it, as the 4.x standard writes it
/// (`module:<course>/<NN>` or `module:<course>/<NN>#<anchor>`). A link with no module index is the
/// course-index defect and does not parse.
class ModuleLink {
  const ModuleLink(this.course, this.index, this.anchor);
  final String course;

  /// The two-digit module index, as written.
  final String index;

  /// The section anchor (`grasp-1`, `week-7-2`), or empty for the top of the module.
  final String anchor;

  static final _pattern = RegExp(r'^module:([A-Za-z0-9._-]+)/(\d{2,3})(?:#([a-z0-9-]+))?$');

  static ModuleLink? parse(String url) {
    final m = _pattern.firstMatch(url.trim());
    return m == null ? null : ModuleLink(m.group(1)!, m.group(2)!, m.group(3) ?? '');
  }

  @override
  String toString() => 'module:$course/$index${anchor.isEmpty ? '' : '#$anchor'}';

  /// BI26102805: whether a lesson file is the module this link names. A 4.x file carries its number inside the
  /// name (`20261006_..._module_02_assets_that_pay_v4_0_0.md`); an older one starts with it (`02_mindset.md`). Until
  /// this, only the second form matched, so every link into a 4.x module did nothing when tapped.
  bool matchesFile(String file) {
    final f = file.toLowerCase();
    if (RegExp('(?:^|[_-])module[_-]?0*${int.parse(index)}(?:[_.-]|\$)').hasMatch(f)) return true;
    return f.startsWith(index) && (f.length == index.length || !RegExp(r'\d').hasMatch(f[index.length]));
  }
}

/// The numbered sections of a module as the reader renders them: `(number, anchor)` per movement and
/// labelled element, in reading order. Exposed so the checker and tests resolve anchors the same way.
List<({String number, String anchor})> moduleSections(String source) =>
    [for (final b in _parseBlocks(source)) if (b.anchor.isNotEmpty) (number: b.number, anchor: b.anchor)];

class MarkdownAnchors {
  final Map<int, GlobalKey> _keys = {};
  List<String> _movements = const [];
  List<int> _words = const [];
  Map<String, int> _anchorIndex = const {};

  /// The block briefly highlighted after a deep link scrolled to it.
  final ValueNotifier<int?> highlighted = ValueNotifier<int?>(null);

  /// Scrolls to the section with [anchor] and highlights it for a moment. False when there is no
  /// such section (or it is not laid out yet).
  bool revealAnchor(String anchor) {
    final i = _anchorIndex[anchor];
    if (i == null || !reveal(i)) return false;
    highlighted.value = i;
    Timer(const Duration(milliseconds: 1800), () {
      if (highlighted.value == i) highlighted.value = null;
    });
    return true;
  }

  bool hasAnchor(String anchor) => _anchorIndex.containsKey(anchor);

  /// How many blocks the last build rendered.
  int get count => _movements.length;

  GlobalKey keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  void _describe(List<String> movements, List<int> words, [Map<String, int> anchorIndex = const {}]) {
    _movements = movements;
    _words = words;
    _anchorIndex = anchorIndex;
  }

  /// The movement (the nearest `##` or `#` heading at or before block [i]).
  String movementOf(int i) => i >= 0 && i < _movements.length ? _movements[i] : '';

  /// Words from block [i] to the end of the module.
  int wordsFrom(int i) {
    var n = 0;
    for (var k = i < 0 ? 0 : i; k < _words.length; k++) {
      n += _words[k];
    }
    return n;
  }

  /// The first block whose bottom edge is below the top of the scroll viewport,
  /// or 0 when nothing is laid out yet.
  int topVisible(ScrollController controller) {
    if (!controller.hasClients) return 0;
    final vp = controller.position.context.storageContext.findRenderObject();
    if (vp is! RenderBox || !vp.attached) return 0;
    final top = vp.localToGlobal(Offset.zero).dy;
    for (var i = 0; i < count; i++) {
      final ro = _keys[i]?.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.attached) continue;
      if (ro.localToGlobal(Offset.zero).dy + ro.size.height > top + 1) return i;
    }
    return count > 0 ? count - 1 : 0;
  }

  /// Scrolls so block [i] sits at the top. False when it does not exist or is not laid out.
  bool reveal(int i) {
    final ctx = _keys[i]?.currentContext;
    if (i < 0 || i >= count || ctx == null) return false;
    Scrollable.ensureVisible(ctx, alignment: 0, duration: Duration.zero);
    return true;
  }

  /// The first block of the movement named [name], or null.
  int? firstBlockOf(String name) {
    final i = _movements.indexOf(name);
    return i < 0 ? null : i;
  }
}

enum _Kind { paragraph, heading, code, quote, rule, listItem, table, callout, chart, map, equation, image, quiz }

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
      RegExp(r'^\*\*(?:What you will learn|What will be learnt|You will be able to|Objective|Outcome|Learning outcomes?):?\*\*\s*',
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
  // Course standard 3.1.0 §8.1: Story (SEE) and Probe (PROBE) are callouts.
  // BI26100537 (standard 4.0.0): the blue callout is Illustration again, whenever no label is authored.
  _Callout('story', 'Illustration', C.callJargon, C.callJargonBg,
      RegExp(r'^\*\*(?:Story|Illustration|Example):?\*\*\s*', caseSensitive: false)),
  _Callout('probe', 'Probe', C.callQuiz, C.callQuizBg,
      RegExp(r'^\*\*Probe:?\*\*\s*', caseSensitive: false)),
  _Callout('fact', 'Fact', C.callFact, C.callFactBg,
      RegExp(r'^\*\*(?:Fun fact|Fact):?\*\*\s*', caseSensitive: false)),
  // BI26100537: the line and rung elements of 4.x (prior, place, point, link, now, week, ...) share
  // a quiet neutral callout. Its pattern never matches: only the `{id}` form claims a line for it.
  _Callout('note', 'Note', C.text3, C.bgRaised, RegExp(r'(?!)')),
  // BI26101804: section 0's objective, the most prominent callout of the module, and the answer to a probe.
  _Callout('objective', 'Objective', C.callLearn, C.callLearnBg, RegExp(r'(?!)')),
  _Callout('answer', 'Answer', C.callQuiz, C.callQuizBg, RegExp(r'^\*\*Answer:?\*\*\s*', caseSensitive: false)),
];

_Callout? _matchCallout(String line) {
  for (final c in _callouts) {
    if (c.pattern.hasMatch(line)) return c;
  }
  return null;
}

/// Standard 4.x §8.1: the element ids, and which callout style each one is drawn in.
const _elementKinds = <String, String>{
  'outcome': 'learn',
  'illustration': 'story',
  'research': 'research',
  'fact': 'fact',
  'probe': 'probe',
  'modelanswer': 'answer',
  // BI26101804 / CI26101803: the tags the content retag uses for section 0 and for probe answers.
  'answer': 'answer',
  'objective': 'objective',
  'prerequisite': 'note',
  'aside': 'note',
  'failure': 'watch',
  'book': 'book',
  'jargon': 'jargon',
  'prior': 'note',
  'place': 'note',
  'point': 'note',
  'link': 'note',
  'proof': 'note',
  'now': 'note',
  'week': 'note',
  'role': 'note',
  'model': 'note',
  'pitfalls': 'note',
  'expert': 'note',
  'essentials': 'note',
  'check': 'note',
  'return': 'note',
  // BI26102804: two 4.x ids the table lacked, so they fell through as plain text with their tag showing.
  'rescore': 'note',
  'scenarios': 'note',
};

/// BI26102804: line-kind elements read as a quiet line (small caps label, one step below body, no box).
const _lineElements = {'prior', 'place', 'point', 'link', 'proof', 'return', 'rescore', 'jargon', 'book'};

/// BI26102804: section-kind elements read as a subheading with their list or table under it, never a callout.
const _sectionElements = {'pitfalls', 'essentials', 'check', 'expert', 'model', 'scenarios'};

/// BI26102804: the APPLY rungs read as one numbered ladder.
const _rungElements = {'now', 'week', 'role'};

/// BI26102804: runs after the section and GUARD rules. Line elements become quiet lines; section elements become
/// a level-3 subheading (their two-word label) followed by their body, if any, and the list or table that follows;
/// APPLY rungs are numbered in order within their movement; a callout with no body and nothing under it is dropped.
List<_Block> _quietElements(List<_Block> blocks) {
  final out = <_Block>[];
  var rung = 0;
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    if (b.kind == _Kind.heading && b.level <= 2) rung = 0;
    if (b.kind != _Kind.callout || b.zeroRole.isNotEmpty || b.elementId.isEmpty) {
      if (b.kind == _Kind.callout && b.text.trim().isEmpty && b.zeroRole.isEmpty && b.callout?.kind != 'answer') continue;
      out.add(b);
      continue;
    }
    final id = b.elementId;
    if (_sectionElements.contains(id)) {
      out.add(_Block(_Kind.heading, text: b.uiLabel.isNotEmpty ? b.uiLabel : id, level: 3)
        ..anchor = b.anchor
        ..number = b.number);
      if (b.text.trim().isNotEmpty) out.add(_Block(_Kind.paragraph, text: b.text)..cite = b.cite);
      continue;
    }
    if (_rungElements.contains(id)) {
      b.zeroRole = 'rung';
      b.rungIndex = ++rung;
      b.demoted = false;
      if (b.text.trim().isNotEmpty || b.uiLabel.isNotEmpty) out.add(b);
      continue;
    }
    if (_lineElements.contains(id)) {
      b.zeroRole = 'line';
      b.demoted = false;
      if (b.text.trim().isNotEmpty) out.add(b);
      continue;
    }
    if (b.text.trim().isEmpty) continue; // no callout is ever drawn empty
    out.add(b);
  }
  return out;
}

/// `**{prior} Before This:** body`, optionally as a list item (`1. **{now} Two Words:** body`).
///
/// BI26101106: `{id!}` marks the element that is its section's one callout.
final _elementLine = RegExp(r'^\*\*\{([a-z]+)(!?)\}\s+(\S+\s+\S+):\*\*\s*(.*)$');

/// `## {orient} Setting Out: Where This Module Begins`.
final _movementHeading = RegExp(r'^##\s+\{([a-z]+)\}\s+(\S+\s+\S+):\s+(.+)$');

/// Standard 4.x §3.10: movements are numbered from 0 in reading order (`k.0`), the labelled elements
/// inside movement k are `k.1`, `k.2`, ... and each gets a stable anchor (`grasp-1`, `week-7-2`).
/// A pre-4.0.0 module is numbered by its `##` headings, with no element numbers or anchors.
void _numberBlocks(List<_Block> blocks) {
  final v4 = blocks.any((b) => b.kind == _Kind.heading && b.movementId.isNotEmpty);
  var k = -1;
  var j = 0;
  for (final b in blocks) {
    if (b.kind == _Kind.heading && b.level == 2 && (!v4 || b.movementId.isNotEmpty)) {
      k++;
      j = 0;
      b.number = '$k.0';
      b.anchor = v4 ? '${b.movementId}-$k' : 'section-$k';
    } else if (b.kind == _Kind.callout && b.elementId.isNotEmpty && k >= 0) {
      j++;
      b.number = '$k.$j';
      b.anchor = '${b.elementId}-$k-$j';
    }
  }
}


/// BI26101804: section 0 of every module, drawn the same way whatever the module's age. The prerequisite is a plain
/// italic line, the objective is the prominent callout, and "Where this fits" is a small grey aside. Content that
/// carries the new tags (`prerequisite`, `objective`, `aside`) is drawn this way as is; older modules are detected by
/// their labels (`Prior:` / the note numbered 0.1, `You will be able to:` / `Outcome`, `Where this fits:`).
void _tagSectionZero(List<_Block> blocks) {
  final v4 = blocks.any((b) => b.kind == _Kind.heading && b.movementId.isNotEmpty);
  var from = 0;
  if (v4) {
    from = blocks.indexWhere((b) => b.kind == _Kind.heading && b.movementId.isNotEmpty);
    if (from < 0) return;
  }
  var to = blocks.length;
  for (var i = from + 1; i < blocks.length; i++) {
    if (blocks[i].kind == _Kind.heading && blocks[i].level == 2) {
      to = i;
      break;
    }
  }
  final label = RegExp(r'^\*\*[^*]{1,40}?\*\*\s*');
  for (var i = from; i < to; i++) {
    final b = blocks[i];
    if (b.kind == _Kind.callout) {
      final id = b.elementId;
      final kind = b.callout?.kind ?? '';
      if (id == 'prior' || id == 'prerequisite' || (kind == 'note' && b.number == '0.1')) {
        b.zeroRole = 'prerequisite';
      } else if (id == 'place' || id == 'aside') {
        b.zeroRole = 'aside';
      } else if (kind == 'learn' || kind == 'objective' || id == 'outcome' || id == 'objective') {
        b.zeroRole = 'objective';
        b.callout = _callouts.firstWhere((c) => c.kind == 'objective');
      }
    } else if (b.kind == _Kind.paragraph) {
      final t = b.text.trimLeft();
      if (RegExp(r'^\*\*(?:Prior|Prerequisites?|Before this):?\*\*', caseSensitive: false).hasMatch(t)) {
        b.zeroRole = 'prerequisite';
        b.text = t.replaceFirst(label, '');
      } else if (RegExp(r'^(?:\*\*)?Where this fits:?(?:\*\*)?', caseSensitive: false).hasMatch(t)) {
        b.zeroRole = 'aside';
        b.text = t.replaceFirst(RegExp(r'^(?:\*\*)?Where this fits:?(?:\*\*)?:?\s*', caseSensitive: false), '');
      }
    }
  }
}

/// BI26101106: one callout per section. Within each movement (between H2s) the element marked
/// `{id!}` is the callout (every marked one, if the author marked several); with none marked, the
/// first callout-kind element is. Every other callout becomes a prose paragraph, so the 935
/// existing modules improve with no rewrite. A model answer is part of its probe, so it keeps its
/// callout and does not count.
void _oneCalloutPerSection(List<_Block> blocks) {
  var start = 0;
  void settle(int end) {
    final inSection = <_Block>[
      for (var i = start; i < end; i++)
        if (blocks[i].kind == _Kind.callout &&
            blocks[i].callout?.kind != 'answer' &&
            blocks[i].zeroRole != 'prerequisite' &&
            blocks[i].zeroRole != 'aside')
          blocks[i],
    ];
    if (inSection.isEmpty) return;
    final marked = inSection.where((b) => b.marked).toList();
    // BI26101804: section 0's objective is its callout.
    final objective = inSection.where((b) => b.zeroRole == 'objective').toList();
    final keep = marked.isNotEmpty || objective.isNotEmpty ? {...marked, ...objective} : {inSection.first};
    for (final b in inSection) {
      if (!keep.contains(b)) b.demoted = true;
    }
  }

  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i].kind == _Kind.heading && blocks[i].level == 2) {
      settle(i);
      start = i + 1;
    }
  }
  settle(blocks.length);
}

String _ensureBoldLabel(String text, [String? fallbackLabel]) {
  final trimmed = text.trim();
  if (trimmed.startsWith('**')) return trimmed;
  if (fallbackLabel != null && fallbackLabel.isNotEmpty) {
    final cleanLabel = fallbackLabel.replaceAll(RegExp(r'[:.*_]+$'), '').trim();
    return '**$cleanLabel:** $trimmed';
  }
  final m = RegExp(r'^(\S+\s+\S+)[:.]\s*(.*)$').firstMatch(trimmed);
  if (m != null) {
    return '**${m.group(1)}:** ${m.group(2)}';
  }
  return trimmed;
}

/// BI26102803: the GUARD movement (5) reads as one core failure, then a numbered list.
/// The callout holds the core failure (an element marked `{failure!}` if the author marked one,
/// else the first); then a subheading (the `{pitfalls}` element's two-word label when there is one,
/// else "Failure modes") and a numbered list of every other failure and every pitfall item,
/// each item opening with its two-word label in bold. No failure is ever shown as a bare paragraph.
List<_Block> _transformGuardSection(List<_Block> section, {String movementNumber = ''}) {
  final failureBlocks = <_Block>[];
  _Block? pitfallsBlock;
  final pitfallItems = <_Block>[];

  for (final b in section) {
    if (b.kind == _Kind.callout && (b.elementId == 'failure' || b.callout?.kind == 'watch')) {
      failureBlocks.add(b);
    } else if (b.kind == _Kind.callout && (b.elementId == 'pitfalls' || b.callout?.kind == 'pitfalls' || b.uiLabel.toLowerCase().contains('pitfall'))) {
      pitfallsBlock = b;
    } else if (b.kind == _Kind.listItem) {
      pitfallItems.add(b);
    }
  }

  if (failureBlocks.isEmpty && pitfallsBlock == null && pitfallItems.isEmpty) {
    return section;
  }

  _Block? coreFailure;
  if (failureBlocks.isNotEmpty) {
    final marked = failureBlocks.where((b) => b.marked).toList();
    coreFailure = marked.isNotEmpty ? marked.first : failureBlocks.first;
    coreFailure.demoted = false;
    if (movementNumber.isNotEmpty) {
      coreFailure.number = '$movementNumber.1';
    }
  }

  final otherFailures = failureBlocks.where((b) => b != coreFailure).toList();
  final remainingItems = <_Block>[];

  var counter = 1;
  for (final f in otherFailures) {
    final label = f.uiLabel.isNotEmpty ? f.uiLabel : 'Failure';
    final text = _ensureBoldLabel(f.text, label);
    final li = _Block(_Kind.listItem, text: text, ordered: true, index: counter++)
      ..anchor = f.anchor
      ..number = f.number;
    remainingItems.add(li);
  }

  if (pitfallsBlock != null && pitfallsBlock.text.trim().isNotEmpty) {
    final text = _ensureBoldLabel(pitfallsBlock.text, pitfallsBlock.uiLabel);
    final li = _Block(_Kind.listItem, text: text, ordered: true, index: counter++)
      ..anchor = pitfallsBlock.anchor
      ..number = pitfallsBlock.number;
    remainingItems.add(li);
  }

  for (final p in pitfallItems) {
    final text = _ensureBoldLabel(p.text);
    final li = _Block(_Kind.listItem, text: text, ordered: true, index: counter++)
      ..anchor = p.anchor
      ..number = p.number;
    remainingItems.add(li);
  }

  final out = <_Block>[];
  final specialBlocks = {...failureBlocks, ?pitfallsBlock, ...pitfallItems};

  var idx = 0;
  while (idx < section.length && !specialBlocks.contains(section[idx])) {
    out.add(section[idx]);
    idx++;
  }

  if (coreFailure != null) {
    out.add(coreFailure);
  }

  if (remainingItems.isNotEmpty) {
    final subheadingText = (pitfallsBlock != null && pitfallsBlock.uiLabel.isNotEmpty)
        ? pitfallsBlock.uiLabel
        : 'Failure modes';
    out.add(_Block(_Kind.heading, text: subheadingText, level: 3));
    out.addAll(remainingItems);
  }

  var lastSpecial = -1;
  for (var k = section.length - 1; k >= 0; k--) {
    if (specialBlocks.contains(section[k])) {
      lastSpecial = k;
      break;
    }
  }
  if (lastSpecial >= 0) {
    for (var k = lastSpecial + 1; k < section.length; k++) {
      if (!specialBlocks.contains(section[k])) {
        out.add(section[k]);
      }
    }
  }

  return out;
}

List<_Block> _applyGuardMovementRule(List<_Block> blocks) {
  final hasAnyH2 = blocks.any((b) => b.kind == _Kind.heading && b.level == 2);
  if (!hasAnyH2 && blocks.any((b) => b.kind == _Kind.callout && (b.elementId == 'failure' || b.elementId == 'pitfalls' || b.callout?.kind == 'watch'))) {
    return _transformGuardSection(blocks);
  }

  final out = <_Block>[];
  var i = 0;
  while (i < blocks.length) {
    if (blocks[i].kind == _Kind.heading && blocks[i].level == 2) {
      final heading = blocks[i];
      out.add(heading);
      final isGuard = heading.movementId == 'guard' ||
          RegExp(r'\bguard\b', caseSensitive: false).hasMatch(heading.text);
      var j = i + 1;
      while (j < blocks.length && !(blocks[j].kind == _Kind.heading && blocks[j].level == 2)) {
        j++;
      }
      final sectionBlocks = blocks.sublist(i + 1, j);
      if (isGuard) {
        final movementNumber = heading.number.contains('.') ? heading.number.split('.').first : '';
        out.addAll(_transformGuardSection(sectionBlocks, movementNumber: movementNumber));
      } else {
        out.addAll(sectionBlocks);
      }
      i = j;
    } else {
      out.add(blocks[i]);
      i++;
    }
  }
  return out;
}

/// One figure of a module, with the parts the page and the viewer show.
class _Figure {
  const _Figure({
    required this.url,
    required this.cacheKey,
    required this.path,
    required this.caption,
    required this.credit,
    required this.captured,
    required this.ratio,
  });
  final String url;
  final String cacheKey;
  final String path;
  final String caption;
  final String credit;
  final String captured;
  final double ratio;
}

class _FigureViewer extends StatefulWidget {
  const _FigureViewer({required this.figures, required this.initial});
  final List<_Figure> figures;
  final int initial;

  @override
  State<_FigureViewer> createState() => _FigureViewerState();
}

class _FigureViewerState extends State<_FigureViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _at = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.figures[_at];
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(children: [
        PageView.builder(
          key: const Key('figure-pages'),
          controller: _pages,
          itemCount: widget.figures.length,
          onPageChanged: (i) => setState(() => _at = i),
          itemBuilder: (_, i) => _ZoomPage(figure: widget.figures[i]),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            key: const Key('figure-close'),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ),
        if (f.caption.isNotEmpty || widget.figures.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)]),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (f.caption.isNotEmpty)
                  Text(f.caption, key: const Key('figure-caption'), style: T.small.copyWith(color: Colors.white)),
                if (widget.figures.length > 1)
                  Text('${_at + 1} / ${widget.figures.length}',
                      style: T.tiny.copyWith(color: Colors.white70)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// One figure in the viewer: pinch to zoom, and pan only while zoomed in, so a one-finger swipe at
/// normal size reaches the page view and turns the page.
class _ZoomPage extends StatefulWidget {
  const _ZoomPage({required this.figure});
  final _Figure figure;

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  final _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final z = _controller.value.getMaxScaleOnAxis() > 1.02;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
        transformationController: _controller,
        panEnabled: _zoomed,
        minScale: 1.0,
        maxScale: 6.0,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.figure.url,
            cacheKey: widget.figure.cacheKey,
            fit: BoxFit.contain,
            errorWidget: (_, _, _) =>
                const Icon(Icons.image_not_supported_rounded, color: Colors.white54, size: 48),
          ),
        ),
      );
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
  String text;
  final int level;
  final bool ordered;
  final int index;
  final List<List<String>> rows;

  /// Set only on callout blocks.
  _Callout? callout;
  String cite = '';

  /// BI26100537 (standard 4.x): the canonical id of a movement or element (never shown), the authored
  /// two-word label (shown), and the computed number and anchor.
  String movementId = '';
  String elementId = '';
  String uiLabel = '';

  /// BI26101106: the author marked this element `{id!}` as its section's callout, and a callout the
  /// section rule turned into a prose paragraph.
  bool marked = false;
  bool demoted = false;

  /// BI26102804: an APPLY rung's place in its movement's ladder (1, 2, 3).
  int rungIndex = 0;

  /// BI26101804: how section 0 draws this block: `prerequisite` (an italic line), `objective` (the prominent
  /// callout) or `aside` (a small grey note). Empty everywhere else.
  String zeroRole = '';
  String number = '';
  String anchor = '';

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

  /// BL26091008/FN26091027: raw markdown body of a `## Check yourself` /
  /// `## Open questions` quiz block -- re-parsed and rendered recursively
  /// rather than flattened at parse time, same reasoning as every other
  /// block that contains prose.
  String quizBody = '';
}

/// Course modules are authored with things a reader must never see: HTML
/// comments (generation provenance), YAML front matter, and legacy ASCII grid
/// tables. BI26100324: strip the first two and turn the third into pipe tables
/// before block parsing. Exposed for tests and the all-modules report.
String normalizeModuleSource(String source) {
  var t = source.replaceAll('\r\n', '\n');
  t = t.replaceFirst(RegExp(r'^\s+'), '');
  // Comments and grid tables are rewritten only OUTSIDE fenced code: an ASCII
  // diagram in a fence is shown verbatim on purpose.
  String outsideFences(String x, String Function(String) f) {
    final out = StringBuffer();
    var pos = 0;
    for (final m in RegExp(r'^[ \t]*```[\s\S]*?^[ \t]*```[^\n]*$', multiLine: true).allMatches(x)) {
      out.write(f(x.substring(pos, m.start)));
      out.write(m.group(0));
      pos = m.end;
    }
    out.write(f(x.substring(pos)));
    return out.toString();
  }

  t = outsideFences(t, (x) => x.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ''));
  t = t.replaceFirst(RegExp(r'^\s+'), '');
  final fm = RegExp(r'^---[ \t]*\n[\s\S]*?\n---[ \t]*(?:\n|$)').firstMatch(t);
  if (fm != null) t = t.substring(fm.end);
  return outsideFences(t, _gridTablesToPipe).trimLeft();
}

bool _isGridBorder(String l) => RegExp(r'^\s*\+[-=:+]{2,}\+\s*$').hasMatch(l);
bool _isGridRow(String l) => RegExp(r'^\s*\|.*\|\s*$').hasMatch(l);

String _gridTablesToPipe(String text) {
  final lines = text.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    if (!_isGridBorder(lines[i])) {
      out.add(lines[i]);
      i++;
      continue;
    }
    // Gather the whole grid: borders and rows.
    final grid = <String>[];
    while (i < lines.length && (_isGridBorder(lines[i]) || _isGridRow(lines[i]))) {
      grid.add(lines[i]);
      i++;
    }
    // Row groups are separated by borders; a `=` border marks the header.
    final groups = <List<List<String>>>[];
    var cur = <List<String>>[];
    var headerGroups = 0;
    for (final l in grid) {
      if (_isGridBorder(l)) {
        if (cur.isNotEmpty) {
          groups.add(cur);
          if (l.contains('=') && headerGroups == 0) headerGroups = groups.length;
          cur = <List<String>>[];
        }
      } else {
        cur.add(_splitRow(l));
      }
    }
    if (cur.isNotEmpty) groups.add(cur);
    if (groups.isEmpty) continue;
    // Merge wrapped cell lines within one group into single cells.
    final rows = <List<String>>[];
    for (final g in groups) {
      final cols = g.map((r) => r.length).reduce((a, b) => a > b ? a : b);
      rows.add(List<String>.generate(
          cols,
          (c) => g.map((r) => c < r.length ? r[c] : '').where((x) => x.isNotEmpty).join(' ')));
    }
    final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    String fmt(List<String> r) =>
        '| ${List<String>.generate(width, (c) => c < r.length ? r[c].replaceAll('|', '/') : '').join(' | ')} |';
    out.add('');
    out.add(fmt(rows.first));
    out.add('|${List.filled(width, ' --- ').join('|')}|');
    for (final r in rows.skip(1)) {
      out.add(fmt(r));
    }
    out.add('');
  }
  return out.join('\n');
}

List<_Block> _parseBlocks(String source) {
  final lines = normalizeModuleSource(source).split('\n');
  var blocks = <_Block>[];
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
      final alt = _plainMarkers(imgMatch.group(1)!.trim());
      final title = _plainMarkers(imgMatch.group(3)?.trim() ?? '');
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
      // A ragged row (a missing or extra `|`) must not throw: Flutter's Table
      // refuses uneven rows and the whole module went blank. Pad to the widest.
      final width = rows.map((r) => r.length).reduce((x, y) => x > y ? x : y);
      for (final r in rows) {
        while (r.length < width) {
          r.add('');
        }
      }
      blocks.add(_Block(_Kind.table, rows: rows));
      continue;
    }

    // FN26091027: `## Check yourself` / `## Open questions` is a quiz
    // callout, not a plain heading -- claimed before the generic heading
    // match below so it doesn't fall through to a bare heading + paragraphs.
    // Mirrors web's learnMd() `/^## (Check yourself|Open questions)/i` branch.
    final quizHeading =
        RegExp(r'^##\s+((?:Check yourself|Open questions).*)$', caseSensitive: false)
            .firstMatch(trimmed);
    if (quizHeading != null) {
      flushPara();
      final title = quizHeading.group(1)!.trim();
      idx++;
      final buf = <String>[];
      while (idx < lines.length && !RegExp(r'^#{1,6}\s').hasMatch(lines[idx].trimLeft())) {
        buf.add(lines[idx]);
        idx++;
      }
      blocks.add(_Block(_Kind.quiz, text: title)..quizBody = buf.join('\n'));
      continue;
    }

    // BI26100537: a 4.x movement heading, `## {id} Two Words: The Heading`.
    final movementHeading = _movementHeading.firstMatch(trimmed);
    if (movementHeading != null) {
      flushPara();
      blocks.add(_Block(_Kind.heading, text: movementHeading.group(3)!.trim(), level: 2)
        ..movementId = movementHeading.group(1)!
        ..uiLabel = movementHeading.group(2)!);
      idx++;
      continue;
    }

    // BI26100537: a 4.x element line, `**{id} Two Words:** body`, also as a list item (APPLY rungs).
    final element = _elementLine.firstMatch(trimmed.replaceFirst(RegExp(r'^\s*(?:\d+[.)]|[-*+])\s+'), ''));
    if (element != null && _elementKinds.containsKey(element.group(1))) {
      flushPara();
      final base = _callouts.firstWhere((c) => c.kind == _elementKinds[element.group(1)]);
      var body = element.group(4)!.trim();
      var cite = '';
      if (base.kind == 'book' || base.kind == 'quote' || base.kind == 'research') {
        final m = RegExp(r'\[([^\]]{4,})\]\s*$').firstMatch(body);
        if (m != null) {
          cite = m.group(1)!;
          body = body.substring(0, m.start).trim();
        }
      }
      blocks.add(_Block(_Kind.callout, text: body)
        ..callout = base
        ..cite = cite
        ..elementId = element.group(1)!
        ..marked = element.group(2) == '!'
        ..uiLabel = element.group(3)!);
      idx++;
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
  _numberBlocks(blocks);
  _tagSectionZero(blocks);
  blocks = _applyGuardMovementRule(blocks);
  _oneCalloutPerSection(blocks);
  blocks = _quietElements(blocks);
  return blocks;
}

/// Captions and alt text are plain strings, so a glossary marker there
/// collapses to its term instead of showing `[[term|definition]]` raw.
String _plainMarkers(String x) => x.replaceAllMapped(
    RegExp(r'\[\[(?:link:)?([^|\]]+)(?:\|[^\]]*)?\]\]'), (m) => m.group(1)!.trim());

List<String> _splitRow(String row) {
  var body = row.trim();
  if (body.startsWith('|')) body = body.substring(1);
  if (body.endsWith('|')) body = body.substring(0, body.length - 1);
  // A `|` inside a `[[term|definition]]` marker belongs to the marker, not to
  // the table: splitting there tore the marker in two and showed raw `[[`.
  final cells = <String>[];
  final cur = StringBuffer();
  var depth = 0;
  for (var i = 0; i < body.length; i++) {
    if (body.startsWith('[[', i)) {
      depth++;
      cur.write('[[');
      i++;
    } else if (depth > 0 && body.startsWith(']]', i)) {
      depth--;
      cur.write(']]');
      i++;
    } else if (body[i] == '|' && depth == 0) {
      cells.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(body[i]);
    }
  }
  cells.add(cur.toString().trim());
  return cells;
}
