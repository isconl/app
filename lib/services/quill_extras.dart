import '../api/client.dart';
import '../util/fmt.dart' as fmt;

/// BI26101508: the rest of the quill studio on the phone, behind one class that alone knows the routes: the Decision
/// Architect binder, article drafting and rewriting, and the hero-image packaging with its progress.
///
/// Nothing here goes outward on its own. Generated text is shown as a proposal the reader accepts or drops, and a
/// package is only asked for by a tap.

class BinderEpisode {
  const BinderEpisode({required this.episodeId, required this.itemId, this.version = '', this.lastModified = ''});
  final String episodeId, itemId, version, lastModified;
  String get day => lastModified.length >= 10 ? lastModified.substring(0, 10) : lastModified;
}

class CompiledEpisode {
  const CompiledEpisode({required this.title, required this.status, required this.linkedinPost});
  final String title, status, linkedinPost;
}

class ImageSite {
  const ImageSite({required this.site, required this.have, required this.expected, this.missing = const []});
  final String site;
  final int have, expected;

  /// "hero 1/3" style lines for the slots still short.
  final List<String> missing;
  bool get short => have < expected;
}

class ImageProgress {
  const ImageProgress({required this.have, required this.want, required this.mb, required this.done, this.sites = const []});
  final int have, want;
  final double mb;
  final bool done;
  final List<ImageSite> sites;

  int get percent => want <= 0 ? 0 : ((have / want) * 100).round().clamp(0, 100);
  List<ImageSite> get shortSites => [for (final s in sites) if (s.short) s];
}

enum ArticleAction { draft, polish }

extension ArticleActionLabel on ArticleAction {
  String get label => this == ArticleAction.draft ? 'Draft' : 'Rewrite';
}

/// The three tones the console offers, with the words it shows.
const articleTones = <(String, String)>[
  ('authoritative', 'Authoritative and deadpan'),
  ('persuasive', 'Persuasive executive'),
  ('technical', 'Technical deep-dive'),
];

/// True when a task's detail mentions the hero-image job, so the progress card shows only there.
bool mentionsHeroImages(Object? detail) => RegExp(r'hero-images|hero_candidates', caseSensitive: false).hasMatch('$detail');

abstract class QuillExtrasApi {
  Future<List<BinderEpisode>> binderEpisodes();
  Future<CompiledEpisode> compileEpisode(String itemId);
  Future<String> generateArticle({required ArticleAction action, required String text, required String title, required String tone, String prompt = ''});
  Future<ImageProgress> imageProgress();

  /// Zips what is sourced so far and returns where it is on the document store.
  Future<({String rel, String name, int images, double mb})> packageImages();
}

class HubQuillExtrasApi implements QuillExtrasApi {
  HubQuillExtrasApi(this.api);
  final ApiClient api;

  static Map<String, dynamic> _ok(dynamic v) {
    final m = fmt.m(v);
    if (m['success'] == false || m['ok'] == false) throw ApiException(0, fmt.s(m['error']).isEmpty ? 'Refused' : fmt.s(m['error']));
    return m;
  }

  @override
  Future<List<BinderEpisode>> binderEpisodes() async {
    final m = _ok(await api.getJson('/api/writer/binder/episodes'));
    return [
      for (final e in fmt.lm(m['episodes']))
        BinderEpisode(episodeId: fmt.s(e['episodeId']), itemId: fmt.s(e['itemId']), version: fmt.s(e['version']), lastModified: fmt.s(e['lastModified'])),
    ];
  }

  @override
  Future<CompiledEpisode> compileEpisode(String itemId) async {
    final m = _ok(await api.getJson('/api/writer/binder/compile?itemId=${Uri.encodeQueryComponent(itemId)}', cold: true));
    return CompiledEpisode(title: fmt.s(m['title']), status: fmt.s(m['status']), linkedinPost: fmt.s(m['linkedinPost']));
  }

  @override
  Future<String> generateArticle({required ArticleAction action, required String text, required String title, required String tone, String prompt = ''}) async {
    final m = _ok(await api.postJson('/api/articles/generate', {'action': action.name, 'prompt': prompt, 'text': text, 'title': title, 'tone': tone}, cold: true));
    return fmt.s(m['text']);
  }

  @override
  Future<ImageProgress> imageProgress() async {
    final m = fmt.m(await api.getJson('/api/images/progress'));
    return ImageProgress(
      have: fmt.i(m['have']),
      want: fmt.i(m['want']),
      mb: fmt.d(m['mb']),
      done: fmt.b(m['done']),
      sites: [
        for (final s in fmt.lm(m['sites']))
          ImageSite(
            site: fmt.s(s['site']),
            have: fmt.i(s['have']),
            expected: fmt.i(s['expected']),
            missing: [
              for (final x in fmt.lm(s['slots']))
                if (fmt.i(x['count']) < 3) '${fmt.s(x['slot'])} ${fmt.i(x['count'])}/3',
            ],
          ),
      ],
    );
  }

  @override
  Future<({String rel, String name, int images, double mb})> packageImages() async {
    final m = _ok(await api.postJson('/api/images/package', {}, cold: true));
    return (rel: fmt.s(m['rel']), name: fmt.s(m['name']), images: fmt.i(m['images']), mb: fmt.d(m['mb']));
  }
}
