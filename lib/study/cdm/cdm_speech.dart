/// BI26101394: a deck document as markdown for the device voice, so a module served only as a document
/// (its markdown `content` empty) still has a Listen bar.
///
/// Only what a reader sees is said: author-only audience blocks and truth checks are left out, as the view
/// leaves them out. Tables, code, charts, maps and embeds come through as markdown the speaker already knows
/// to skip and announce.
library;

import 'cdm_model.dart';

String cdmSpeakableMarkdown(CdmDoc doc) {
  final out = StringBuffer();
  void para(String s) {
    if (s.trim().isEmpty) return;
    out
      ..writeln(s.trim())
      ..writeln();
  }

  void node(CdmNode n) {
    switch (n.type) {
      case 'heading':
        para('${'#' * n.intOf('level', 2).clamp(1, 6)} ${n.str('text')}');
      case 'paragraph':
        para(n.str('text'));
      case 'quote':
        final by = n.strOrNull('attribution');
        para(by == null ? n.str('text') : '${n.str('text')} ($by)');
      case 'bullets':
      case 'ordered':
        para([for (final i in n.strList('items')) '- $i'].join('\n'));
      case 'checked_bullets':
        para([for (final i in n.mapList('items')) '- ${i['text'] ?? ''}'].join('\n'));
      case 'kv_list':
        para([for (final i in n.mapList('items')) '- ${i['label'] ?? ''}: ${i['value'] ?? ''}'].join('\n'));
      case 'callout':
        final title = n.strOrNull('title');
        para(title == null ? n.str('text') : '$title. ${n.str('text')}');
      case 'image':
        final alt = n.str('alt').trim();
        if (alt.isNotEmpty) para('Image: $alt.');
      case 'equation':
        para('(formula, see screen)');
      case 'table':
        // Kept as a markdown table so speakable() skips and announces it.
        final header = n.strList('header');
        final cols = header.isEmpty ? 1 : header.length;
        para('| ${header.isEmpty ? ' ' : header.join(' | ')} |\n|${List.filled(cols, '---').join('|')}|');
      case 'code':
        para('```${n.str('language')}\n${n.str('text')}\n```');
      case 'chart':
      case 'map':
      case 'embed':
        para('```${n.type}\n```');
      case 'section':
        for (final c in n.children) {
          node(c);
        }
      case 'audience':
        if (!n.strList('aud').contains('author')) {
          for (final c in n.children) {
            node(c);
          }
        }
      default:
        // truth_check, breaks and kinds this build does not know: nothing to say.
        break;
    }
  }

  para('# ${doc.headline}');
  if (doc.subtitle != null) para(doc.subtitle!);
  for (final n in doc.sections) {
    node(n);
  }
  return out.toString();
}
