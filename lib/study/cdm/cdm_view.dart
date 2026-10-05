/// BI26092620: draws a deck document natively, one widget per block kind.
///
/// Every block is wrapped in a [KeyedSubtree] keyed `cdm-<block id>`, so notes and
/// the module lifecycle can anchor to a block (BI26092613, BI26092614). A kind this
/// build does not know renders a neutral "needs an app update" box and logs once;
/// it never breaks the page. Inline marks inside text (emphasis, links, jargon
/// markers) go through the existing [Markdown] reader so a module looks the same
/// whichever path served it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';
import '../../util/markdown.dart';
import 'cdm_cache.dart';
import 'cdm_model.dart';

/// Display label and colour of the twelve v3 callouts (labels as deck prints them).
class CdmCalloutStyle {
  const CdmCalloutStyle(this.label, this.colour, this.background);
  final String label;
  final Color colour;
  final Color background;
}

Color _tint(Color c) => c.withValues(alpha: 0.10);

final Map<String, CdmCalloutStyle> cdmCalloutStyles = {
  'prior': CdmCalloutStyle('Prior', const Color(0xFF8B9EB7), _tint(const Color(0xFF8B9EB7))),
  'outcome': const CdmCalloutStyle('Outcome', C.callLearn, C.callLearnBg),
  'place': CdmCalloutStyle('Place', const Color(0xFFB08F6A), _tint(const Color(0xFFB08F6A))),
  'story': const CdmCalloutStyle('Story', C.callQuote, C.callQuoteBg),
  'jargon': const CdmCalloutStyle('In plain language', C.callJargon, C.callJargonBg),
  'book': const CdmCalloutStyle('Book', C.callBook, C.callBookBg),
  'research': const CdmCalloutStyle('Research', C.callResearch, C.callResearchBg),
  'fact': const CdmCalloutStyle('Fact', C.callFact, C.callFactBg),
  'probe': CdmCalloutStyle('Probe', const Color(0xFFE5719E), _tint(const Color(0xFFE5719E))),
  'failure': const CdmCalloutStyle('Failure', C.callWatch, C.callWatchBg),
  'essentials': CdmCalloutStyle('Essentials', C.greenBright, _tint(C.greenBright)),
  'check': const CdmCalloutStyle('Check', C.callQuiz, C.callQuizBg),
};

/// Kinds already reported, so one unknown kind logs once per run, not per frame.
final Set<String> _reportedUnknown = <String>{};

@visibleForTesting
void resetCdmUnknownLog() => _reportedUnknown.clear();

class CdmView extends StatelessWidget {
  const CdmView(
    this.doc, {
    super.key,
    this.cache,
    this.imageFetch,
    this.courseId = '',
    this.baseUrl = '',
    this.token = '',
    this.showHeader = false,
  });

  final CdmDoc doc;

  /// When set, images are read from and kept in the on-device cache.
  final CdmCache? cache;
  final CdmImageFetch? imageFetch;

  // Forwarded to the inline reader for any `_assets/` links inside text.
  final String courseId;
  final String baseUrl;
  final String token;

  /// The lesson screen draws its own header; set this to also draw the headline.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (showHeader && doc.headline.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(doc.headline, style: T.title.copyWith(fontSize: 22)),
        ),
      for (final n in doc.sections) _block(n),
      if (doc.footerNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(doc.footerNote!, style: T.tiny),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _text(String text, {TextStyle? style}) => Markdown(
        text,
        variant: MarkdownVariant.reading,
        baseStyle: style,
        courseId: courseId,
        baseUrl: baseUrl,
        token: token,
      );

  Widget _block(CdmNode n) => KeyedSubtree(key: ValueKey('cdm-${n.id}'), child: _render(n));

  Widget _blocks(List<CdmNode> ns) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final n in ns) _block(n)]);

  Widget _render(CdmNode n) {
    if (!n.known) return _unknown(n);
    switch (n.type) {
      case 'heading':
        return _heading(n);
      case 'paragraph':
        return _text(n.str('text'));
      case 'bullets':
        return _bullets(n);
      case 'checked_bullets':
        return _checkedBullets(n);
      case 'kv_list':
        return _kvList(n);
      case 'truth_check':
        return const SizedBox.shrink(); // author-facing: never part of what a reader sees
      case 'table':
        return _table(n);
      case 'section':
        return _section(n);
      case 'audience':
        return n.strList('aud').contains('author') ? const SizedBox.shrink() : _blocks(n.children);
      case 'page_break':
        return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: C.border, height: 1));
      case 'slide_break':
        return const SizedBox.shrink();
      case 'quote':
        return _quote(n);
      case 'code':
        return _code(n);
      case 'ordered':
        return _ordered(n);
      case 'chart':
        return _chart(n);
      case 'image':
        return _image(n);
      case 'embed':
        return _embed(n);
      case 'callout':
        return _callout(n);
      case 'equation':
        return _equation(n);
      case 'map':
        return _map(n);
    }
    return _unknown(n);
  }

  // ---- text blocks ----

  Widget _heading(CdmNode n) {
    final level = n.intOf('level', 2).clamp(1, 6);
    final size = const [24.0, 20.0, 17.0, 15.5, 15.0, 14.0][level - 1];
    return Padding(
      padding: EdgeInsets.only(top: level <= 2 ? 22 : 14, bottom: 6),
      child: Text(n.str('text'),
          style: T.title.copyWith(fontSize: size, height: 1.3, fontWeight: FontWeight.w700)),
    );
  }

  Widget _bullets(CdmNode n) {
    final items = n.strList('items');
    final details = n.json['details'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(width: 22, child: Text('•', style: TextStyle(color: C.text3, fontSize: 16, height: 1.5))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _text(items[i]),
                  if (details is List && i < details.length && details[i] is String && (details[i] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(details[i] as String, style: T.body2.copyWith(color: C.text3)),
                    ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _ordered(CdmNode n) {
    final items = n.strList('items');
    final start = n.intOf('start', 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 28,
                child: Text('${start + i}.', style: T.body.copyWith(color: C.text3, height: 1.72)),
              ),
              Expanded(child: _text(items[i])),
            ]),
          ),
      ]),
    );
  }

  Widget _checkedBullets(CdmNode n) {
    final items = n.mapList('items');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 3, right: 8),
                child: Icon(Icons.check_circle_outline_rounded, size: 16, color: C.green),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _text('${it['text'] ?? ''}'),
                  if ('${it['reason'] ?? ''}'.isNotEmpty)
                    Text('${it['reason']}', style: T.body2.copyWith(color: C.text3)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _kvList(CdmNode n) {
    final items = n.mapList('items');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.bgRaised,
        border: Border.all(color: C.border),
        borderRadius: BorderRadius.circular(Sz.rMd),
      ),
      child: Column(children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 120, child: Text('${it['label'] ?? ''}', style: T.label)),
              Expanded(child: Text('${it['value'] ?? ''}', style: T.body)),
            ]),
          ),
      ]),
    );
  }

  Widget _quote(CdmNode n) {
    final attribution = n.strOrNull('attribution');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: C.borderMid, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n.str('text'), style: T.body.copyWith(fontStyle: FontStyle.italic, fontSize: 15.5, height: 1.7)),
        if (attribution != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('— $attribution', style: T.body2.copyWith(color: C.text3)),
          ),
      ]),
    );
  }

  Widget _code(CdmNode n) {
    final language = n.strOrNull('language');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.bgRaised,
        border: Border.all(color: C.border),
        borderRadius: BorderRadius.circular(Sz.rMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (language != null) Text(language.toUpperCase(), style: T.label),
        if (language != null) const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(n.str('text'), style: T.mono.copyWith(fontSize: 12.5, height: 1.5, color: C.text)),
        ),
      ]),
    );
  }

  Widget _table(CdmNode n) {
    final header = n.strList('header');
    final rowsRaw = n.json['rows'];
    final rows = <List<String>>[
      if (rowsRaw is List)
        for (final r in rowsRaw)
          if (r is List) [for (final c in r) '$c']
    ];
    if (header.isEmpty && rows.isEmpty) return const SizedBox.shrink();
    final cols = math.max(header.length, rows.fold<int>(0, (m, r) => math.max(m, r.length)));
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
          decoration: head ? const BoxDecoration(color: C.surface) : null,
          children: [
            for (var i = 0; i < cols; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(
                  i < cells.length ? cells[i] : '',
                  style: T.body2.copyWith(
                      color: head ? C.text : C.text2, fontWeight: head ? FontWeight.w600 : FontWeight.w400, height: 1.45),
                ),
              ),
          ],
        );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(Sz.rMd)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: const TableBorder(horizontalInside: BorderSide(color: C.border)),
          children: [
            if (header.isNotEmpty) row(header, head: true),
            for (final r in rows) row(r),
          ],
        ),
      ),
    );
  }

  // ---- groups ----

  static final _quizTitle = RegExp(r'^\s*(check yourself|open questions)\s*:?\s*$', caseSensitive: false);

  Widget _section(CdmNode n) {
    final title = n.str('title');
    if (_quizTitle.hasMatch(title)) return _CdmQuiz(title: title, child: _blocks(n.children));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(title, style: T.title.copyWith(fontSize: 19, height: 1.3, fontWeight: FontWeight.w700)),
        ),
      _blocks(n.children),
    ]);
  }

  Widget _callout(CdmNode n) {
    final kind = n.calloutKind;
    final style = kind == null
        ? const CdmCalloutStyle('Note', C.text3, Color(0x1A7D8590))
        : cdmCalloutStyles[kind]!;
    final title = n.strOrNull('title');
    final citation = n.strOrNull('citation');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: style.background,
        border: Border(left: BorderSide(color: style.colour, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(Sz.rMd),
          bottomRight: Radius.circular(Sz.rMd),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          (title ?? style.label).toUpperCase(),
          style: T.mono.copyWith(fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w600, color: style.colour),
        ),
        const SizedBox(height: 5),
        _text(n.str('text'), style: kind == 'story' ? T.body.copyWith(fontStyle: FontStyle.italic) : null),
        if (citation != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(citation, style: T.mono.copyWith(fontSize: 10.5, height: 1.5, color: C.text3)),
          ),
      ]),
    );
  }

  // ---- figures ----

  Widget _equation(CdmNode n) {
    final tex = n.str('tex');
    final display = n.boolOf('display');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.bgRaised,
        border: Border.all(color: C.borderMid),
        borderRadius: BorderRadius.circular(Sz.rMd),
      ),
      child: Align(
        alignment: display ? Alignment.center : Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            tex,
            mathStyle: display ? MathStyle.display : MathStyle.text,
            textStyle: T.body.copyWith(fontSize: display ? 18 : 16, color: C.text),
            // A formula the typesetter cannot parse shows its source: never a crash.
            onErrorFallback: (_) => Text(tex, style: T.mono.copyWith(fontSize: 14, color: C.text, fontStyle: FontStyle.italic)),
          ),
        ),
      ),
    );
  }

  Widget _figureFrame(Widget child, {String? caption}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          child,
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(caption, style: T.body2.copyWith(color: C.text3, fontStyle: FontStyle.italic)),
            ),
        ]),
      );

  Widget _image(CdmNode n) {
    final src = n.str('src');
    final alt = n.str('alt');
    return _figureFrame(
      ClipRRect(
        borderRadius: BorderRadius.circular(Sz.rMd),
        child: CdmImage(src: src, alt: alt, cache: cache, fetch: imageFetch),
      ),
      caption: n.strOrNull('caption'),
    );
  }

  Widget _embed(CdmNode n) {
    final url = n.str('url');
    return _figureFrame(
      InkWell(
        onTap: () => _open(url),
        borderRadius: BorderRadius.circular(Sz.rMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: C.bgRaised,
            border: Border.all(color: C.border),
            borderRadius: BorderRadius.circular(Sz.rMd),
          ),
          child: Row(children: [
            const Icon(Icons.open_in_new_rounded, size: 18, color: C.cyan),
            const SizedBox(width: 10),
            Expanded(child: Text(url, style: T.body2.copyWith(color: C.cyan), maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
      caption: n.strOrNull('caption'),
    );
  }

  Widget _chart(CdmNode n) {
    final kind = n.str('kind');
    final title = n.strOrNull('title');
    final points = <({String label, double value})>[
      for (final p in n.mapList('data'))
        (label: '${p['label'] ?? ''}', value: (p['value'] is num) ? (p['value'] as num).toDouble() : 0.0)
    ];
    return _figureFrame(
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.bgRaised,
          border: Border.all(color: C.border),
          borderRadius: BorderRadius.circular(Sz.rMd),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((title ?? 'Chart').toUpperCase(), style: T.label.copyWith(color: C.amber, fontSize: 9.5)),
          const SizedBox(height: 10),
          if (points.isEmpty)
            Text('No data', style: T.body2.copyWith(color: C.text3))
          else if (kind == 'line')
            SizedBox(height: 140, child: CustomPaint(painter: _LinePainter(points), size: Size.infinite))
          else if (kind == 'pie')
            _pie(points)
          else
            _bars(points),
        ]),
      ),
    );
  }

  Widget _bars(List<({String label, double value})> points) {
    final maxV = points.map((p) => p.value.abs()).fold<double>(0, math.max);
    final safe = maxV == 0 ? 1.0 : maxV;
    return Column(children: [
      for (final p in points)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 92, child: Text(p.label, style: T.body2, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Stack(children: [
                Container(height: 14, decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(3))),
                FractionallySizedBox(
                  widthFactor: (p.value.abs() / safe).clamp(0.0, 1.0),
                  child: Container(height: 14, decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(3))),
                ),
              ]),
            ),
            SizedBox(width: 54, child: Text(_num(p.value), textAlign: TextAlign.right, style: T.mono.copyWith(fontSize: 11))),
          ]),
        ),
    ]);
  }

  static const _pieColours = [C.green, C.cyan, C.amber, C.violet, C.callQuote, C.callQuiz, C.red, C.callFact];

  Widget _pie(List<({String label, double value})> points) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(width: 110, height: 110, child: CustomPaint(painter: _PiePainter(points, _pieColours))),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < points.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _pieColours[i % _pieColours.length], shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text('${points[i].label}  ${_num(points[i].value)}', style: T.body2)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  // ---- map ----

  Widget _map(CdmNode n) {
    final spec = n.str('spec');
    double? num(String key) {
      final m = RegExp('^\\s*$key\\s*:\\s*(-?\\d+(?:\\.\\d+)?)', caseSensitive: false, multiLine: true).firstMatch(spec);
      return m == null ? null : double.tryParse(m.group(1)!);
    }

    final lat = num('lat');
    final lon = num('lon') ?? num('lng');
    final zoom = (num('zoom') ?? 13).round().clamp(1, 18);
    final labelMatch = RegExp(r'^\s*label\s*:\s*(.+)$', caseSensitive: false, multiLine: true).firstMatch(spec);
    final label = n.strOrNull('caption') ?? labelMatch?.group(1)?.trim() ?? 'Map';
    final hasPoint = lat != null && lon != null;
    final tileUrl = hasPoint ? _tileUrl(lat, lon, zoom) : null;
    final openUrl = hasPoint ? 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=$zoom/$lat/$lon' : null;
    return _figureFrame(
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: C.bgRaised,
          border: Border.all(color: C.border),
          borderRadius: BorderRadius.circular(Sz.rMd),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (tileUrl != null)
            SizedBox(
              height: 150,
              child: CdmImage(src: tileUrl, alt: 'Map of $label', cache: cache, fetch: imageFetch, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.map_rounded, size: 22, color: C.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: T.body.copyWith(fontWeight: FontWeight.w600)),
                  if (hasPoint) Text('$lat, $lon (zoom $zoom)', style: T.mono.copyWith(fontSize: 11, color: C.text3)),
                  if (hasPoint) Text('© OpenStreetMap contributors', style: T.tiny),
                ]),
              ),
              if (openUrl != null)
                TextButton(onPressed: () => _open(openUrl), child: const Text('Open map')),
            ]),
          ),
          if (!hasPoint)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(spec, style: T.mono.copyWith(fontSize: 11.5, color: C.text3)),
            ),
        ]),
      ),
    );
  }

  /// The slippy-map tile that contains a point.
  static String _tileUrl(double lat, double lon, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    final x = ((lon + 180) / 360 * n).floor().clamp(0, n.toInt() - 1);
    final latRad = lat * math.pi / 180;
    final y = ((1 - (math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi)) / 2 * n).floor().clamp(0, n.toInt() - 1);
    return 'https://tile.openstreetmap.org/$zoom/$x/$y.png';
  }

  // ---- fallback ----

  Widget _unknown(CdmNode n) {
    if (_reportedUnknown.add(n.type)) {
      debugPrint('cdm: unknown block kind "${n.type}" (needs an app update); shown as a placeholder');
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.bgRaised,
        border: Border.all(color: C.border),
        borderRadius: BorderRadius.circular(Sz.rMd),
      ),
      child: Row(children: [
        const Icon(Icons.system_update_alt_rounded, size: 18, color: C.text3),
        const SizedBox(width: 10),
        Expanded(child: Text('This part needs an app update', style: T.body2.copyWith(color: C.text3))),
      ]),
    );
  }

  static Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* nothing sensible to do on a platform without a handler */}
  }
}

/// A "Check yourself" / "Open questions" group: the answers stay hidden until asked for.
class _CdmQuiz extends StatefulWidget {
  const _CdmQuiz({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  State<_CdmQuiz> createState() => _CdmQuizState();
}

class _CdmQuizState extends State<_CdmQuiz> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: const BoxDecoration(
        color: C.callQuizBg,
        border: Border(left: BorderSide(color: C.callQuiz, width: 3)),
        borderRadius: BorderRadius.only(topRight: Radius.circular(Sz.rMd), bottomRight: Radius.circular(Sz.rMd)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: C.callQuiz, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 11, color: C.bgRaised),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(widget.title.toUpperCase(),
                style: T.mono.copyWith(fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w600, color: C.callQuiz)),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: C.callQuiz,
            ),
            onPressed: () => setState(() => _revealed = !_revealed),
            child: Text(_revealed ? 'Hide' : 'Reveal', style: T.mono.copyWith(fontSize: 9.5, color: C.callQuiz)),
          ),
        ]),
        if (_revealed) ...[const SizedBox(height: 5), widget.child],
      ]),
    );
  }
}

/// An image that comes from the on-device cache when it can, from the network once
/// otherwise, and shows its alt text when neither works.
class CdmImage extends StatefulWidget {
  const CdmImage({super.key, required this.src, required this.alt, this.cache, this.fetch, this.fit = BoxFit.contain});
  final String src;
  final String alt;
  final CdmCache? cache;
  final CdmImageFetch? fetch;
  final BoxFit fit;

  @override
  State<CdmImage> createState() => _CdmImageState();
}

class _CdmImageState extends State<CdmImage> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    final cache = widget.cache;
    final fetch = widget.fetch;
    if (cache != null && fetch != null && widget.src.isNotEmpty) {
      _bytes = cache.image(widget.src, fetch);
    }
  }

  Widget _alt() => Container(
        padding: const EdgeInsets.all(14),
        color: C.bgRaised,
        child: Row(children: [
          const Icon(Icons.image_not_supported_outlined, size: 18, color: C.text3),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.alt.isEmpty ? 'Image unavailable' : widget.alt, style: T.body2.copyWith(color: C.text3))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.src.isEmpty) return _alt();
    final bytes = _bytes;
    if (bytes == null) {
      return Image.network(
        widget.src,
        fit: widget.fit,
        semanticLabel: widget.alt,
        errorBuilder: (_, _, _) => _alt(),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: bytes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final data = snap.data;
        if (data == null) return _alt();
        return Image.memory(data, fit: widget.fit, semanticLabel: widget.alt, errorBuilder: (_, _, _) => _alt());
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.points);
  final List<({String label, double value})> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final values = points.map((p) => p.value).toList();
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    const padX = 8.0, padY = 10.0;
    final w = size.width - padX * 2, h = size.height - padY * 2;
    Offset at(int i) => Offset(
          padX + (points.length == 1 ? w / 2 : w * i / (points.length - 1)),
          padY + h - h * (values[i] - lo) / span,
        );
    final axis = Paint()
      ..color = C.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(padX, size.height - padY), Offset(size.width - padX, size.height - padY), axis);
    final line = Paint()
      ..color = C.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = C.greenBright;
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(at(i), 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.points != points;
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.points, this.colours);
  final List<({String label, double value})> points;
  final List<Color> colours;

  @override
  void paint(Canvas canvas, Size size) {
    final total = points.fold<double>(0, (s, p) => s + p.value.abs());
    if (total == 0) return;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    var start = -math.pi / 2;
    for (var i = 0; i < points.length; i++) {
      final sweep = 2 * math.pi * points[i].value.abs() / total;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = colours[i % colours.length]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.points != points;
}
