import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/markdown.dart';

/// A reading surface.
///
/// Everywhere else in this app content sits in a `Panel`: bordered, tinted,
/// shadowed, deliberately card-like. That is right for a task, a balance, an
/// audit entry. It is wrong for a learning module, which is 3,000 words of
/// prose that happen to arrive as markdown. A border around a page of text
/// tells the eye "this is a component" when what you want it to say is
/// "this is a page".
///
/// So the reader drops the box entirely. Text sits on the page ground, at one
/// measure, with vertical rhythm doing the work the border used to do. The
/// only chrome is a hairline progress line at the very top, which is the one
/// thing a long module actually needs.
///
/// Measure: capped at 700 logical pixels and centred. On a 390px phone that
/// is a no-op and the text simply runs the width of the page less its margins.
/// On a Windows or Linux window it stops the line length running to 1,400px,
/// which is unreadable regardless of how good the type is.
class ReadingSurface extends StatelessWidget {
  const ReadingSurface({
    super.key,
    required this.children,
    this.maxWidth = 700,
  });

  final List<Widget> children;
  final double maxWidth;

  /// Horizontal page margin. Slightly generous on purpose: the thumb rests on
  /// the edge of a phone and text under the thumb is text you re-read.
  static const hPad = 20.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + hPad * 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: hPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// The prose itself. Selectable, because the second thing you do with a good
/// paragraph is quote it.
class ReadingBody extends StatelessWidget {
  const ReadingBody(this.markdown,
      {super.key, this.courseId = '', this.baseUrl = ''});
  final String markdown;
  /// Passed to [Markdown] so `_assets/` image paths resolve to the hub API.
  final String courseId;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Markdown(markdown,
          variant: MarkdownVariant.reading,
          courseId: courseId,
          baseUrl: baseUrl),
    );
  }
}

/// The title block a reading page opens with: kicker, title, meta line.
///
/// The app bar already carries the title, but an app bar title is 16px and
/// truncates. A module deserves the real thing at the top of its own page,
/// and it gives the reader somewhere to land before the prose starts.
class ReadingHeader extends StatelessWidget {
  const ReadingHeader({
    super.key,
    required this.title,
    this.kicker,
    this.meta,
    this.trailing,
  });

  final String title;

  /// Small uppercase line above the title - the course, the space, the source.
  final String? kicker;

  /// One quiet line under the title: word count, reading time, status.
  final String? meta;

  /// Sits under the meta line, full width. Status pills go here.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        if (kicker != null && kicker!.isNotEmpty) ...[
          Text(kicker!.toUpperCase(), style: T.label.copyWith(color: C.green)),
          const SizedBox(height: 9),
        ],
        SelectionArea(
          child: Text(
            title,
            style: T.headline.copyWith(
                fontSize: 25, height: 1.22, letterSpacing: -0.6),
          ),
        ),
        if (meta != null && meta!.isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(meta!, style: T.tiny.copyWith(color: C.text3, fontSize: 11.5)),
        ],
        if (trailing != null) ...[
          const SizedBox(height: 16),
          trailing!,
        ],
        const SizedBox(height: 10),
        const Divider(),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Hairline reading-progress line, pinned under the app bar.
///
/// The one flourish on this surface, and it is load-bearing rather than
/// decorative: a learning module built to the depth standard runs long enough
/// that "how much is left" is a real question, and a scrollbar on a phone
/// answers it for about half a second.
class ReadingProgress extends StatelessWidget {
  const ReadingProgress({super.key, required this.controller});
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        double fraction = 0;
        if (controller.hasClients) {
          final p = controller.position;
          if (p.maxScrollExtent > 0) {
            fraction = (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
          }
        }
        return SizedBox(
          height: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                decoration: const BoxDecoration(
                  color: C.green,
                  boxShadow: [
                    BoxShadow(color: C.greenGlow, blurRadius: 6, spreadRadius: 0),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A borderless section on a reading page: hairline rule, label, content.
/// Used for "Your notes" under a lesson, so the form does not reintroduce a
/// card directly beneath borderless prose.
class ReadingSection extends StatelessWidget {
  const ReadingSection({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 34),
        const Divider(),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(label.toUpperCase(), style: T.label),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Rough reading time, for the meta line. 220 wpm is a sensible middle for
/// dense technical prose read on a phone.
String readingMeta(String markdown) {
  final words = markdown
      .split(RegExp(r'\s+'))
      .where((w) => w.trim().isNotEmpty)
      .length;
  if (words == 0) return '';
  final minutes = (words / 220).ceil();
  return '$words words · $minutes min read';
}
