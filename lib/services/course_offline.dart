import '../data/modules.dart';
import 'audio_downloads.dart';

/// The `_assets/` files a module's markdown refers to: images in `![alt](_assets/x.png)`
/// form and `src="_assets/x.png"` in embedded HTML, each once, in reading order.
List<String> assetFilesIn(String markdown) {
  final seen = <String>{};
  final out = <String>[];
  for (final m in RegExp(r'''(?:\]\(|src=["'])\s*(?:\./)?_assets/([^)"'\s]+)''').allMatches(markdown)) {
    final f = m.group(1)!;
    if (seen.add(f)) out.add(f);
  }
  return out;
}

/// The URL the reader loads an asset from. It must match what the reading surface
/// builds, byte for byte, because the image cache is keyed by URL: a warmed image is
/// only a hit if this is the same string the reader asks for later.
String assetUrl({required String baseUrl, required String token, required String course, required String file}) {
  final base = baseUrl.trimRight().replaceAll(RegExp(r'/$'), '');
  return '$base/api/learning/asset?course=${Uri.encodeComponent(course)}'
      '&file=${Uri.encodeComponent(file)}&token=${Uri.encodeComponent(token)}';
}

/// One run of "take this course offline": the module text, the images the text
/// uses, and the narration, in that order, with the phases reported as they go.
class CourseOfflineResult {
  CourseOfflineResult({
    required this.modules,
    required this.images,
    required this.audio,
    required this.notes,
  });
  final int modules;
  final int images;
  final int audio;

  /// Plain sentences about anything that did not finish.
  final List<String> notes;
}

typedef WarmImage = Future<bool> Function(String url);

class CourseOffline {
  CourseOffline({
    required this.modules,
    required this.baseUrl,
    required this.token,
    required this.warmImage,
    this.audio,
  });

  final ModuleLibrary modules;
  final String Function() baseUrl;
  final String Function() token;

  /// Fetches one image into the image cache; true when it is there afterwards.
  final WarmImage warmImage;
  final AudioDownloads? audio;

  Future<CourseOfflineResult> run(
    String course,
    List<String> files, {
    void Function(String phase, int done, int total)? onProgress,
  }) async {
    final notes = <String>[];

    final textDone = await modules.downloadCourse(course, files, onProgress: (d, t) => onProgress?.call('text', d, t));
    if (textDone < files.length) notes.add('${files.length - textDone} modules did not download. Try again with a signal.');

    // Images the downloaded modules use.
    final urls = <String>[];
    for (final f in files) {
      final md = await modules.markdownOf(course, f);
      for (final a in assetFilesIn(md)) {
        urls.add(assetUrl(baseUrl: baseUrl(), token: token(), course: course, file: a));
      }
    }
    final unique = urls.toSet().toList();
    var imgDone = 0;
    for (final u in unique) {
      if (await warmImage(u)) imgDone++;
      onProgress?.call('images', imgDone, unique.length);
    }
    if (imgDone < unique.length) notes.add('${unique.length - imgDone} images did not download.');

    // Narration where the agent has made it.
    var audioDone = 0;
    final dl = audio;
    if (dl != null) {
      final wanted = <({String file, String rev})>[];
      for (final f in files) {
        final a = modules.audioFor(course, f);
        if (a != null && a['available'] == true && a['stale'] != true) {
          wanted.add((file: f, rev: '${a['rev'] ?? ''}'));
        }
      }
      for (final m in wanted) {
        try {
          await dl.download(course: course, file: m.file, rev: m.rev);
          audioDone++;
        } on AudioDownloadException catch (e) {
          notes.add(e.message);
          break; // the same reason applies to the rest (Wi-Fi, no signal)
        }
        onProgress?.call('audio', audioDone, wanted.length);
      }
    }

    return CourseOfflineResult(modules: textDone, images: imgDone, audio: audioDone, notes: notes);
  }
}
