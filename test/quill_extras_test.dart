// BI26101508: the binder, article drafting and the image-packaging card, each against a fake api. Nothing leaves the
// device: generated text is only a proposal, and a package is made on a tap.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/services/documents.dart';
import 'package:isconl/services/quill_extras.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/widgets/quill_extras_widgets.dart';

import 'support/test_services.dart';

class _FakeQuill implements QuillExtrasApi {
  List<BinderEpisode> episodes = const [BinderEpisode(episodeId: '07', itemId: 'it7', version: '1.2', lastModified: '2026-10-01T10:00:00Z')];
  Object? generateError;
  final calls = <String>[];
  int progressCalls = 0;
  ImageProgress progress = const ImageProgress(
    have: 30,
    want: 60,
    mb: 12.5,
    done: false,
    sites: [ImageSite(site: 'alpha', have: 10, expected: 20, missing: ['hero 1/3']), ImageSite(site: 'beta', have: 20, expected: 20)],
  );

  @override
  Future<List<BinderEpisode>> binderEpisodes() async => episodes;

  @override
  Future<CompiledEpisode> compileEpisode(String itemId) async {
    calls.add('compile:$itemId');
    return const CompiledEpisode(title: 'Episode 07: the vendor call', status: 'ready', linkedinPost: 'Most vendor calls are decided before they start.');
  }

  @override
  Future<String> generateArticle({required ArticleAction action, required String text, required String title, required String tone, String prompt = ''}) async {
    calls.add('${action.name}:$tone:$prompt');
    if (generateError != null) throw generateError!;
    return 'REWRITTEN: $text';
  }

  @override
  Future<ImageProgress> imageProgress() async {
    progressCalls++;
    return progress;
  }

  @override
  Future<({String rel, String name, int images, double mb})> packageImages() async {
    calls.add('package');
    return (rel: 'hero-images.zip', name: 'hero-images.zip', images: 30, mb: 12.5);
  }
}

class _FakeDocs implements DocumentsApi {
  @override
  Future<({String filename, List<int> bytes})> rawFile(String rel) async =>
      (filename: rel, bytes: rel.endsWith('.zip') ? const [1, 2, 3] : utf8.encode('The original article text.'));

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  Future<void> pumpIn(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final services = (await t.runAsync(() => buildTestServices(ScriptedApi({}))))!;
    await t.pumpWidget(AppScope(services: services, child: MaterialApp(theme: buildTheme(), home: Scaffold(body: w))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  test('the percent is computed from have and want, and only short sites are listed', () {
    const p = ImageProgress(have: 30, want: 60, mb: 1, done: false, sites: [ImageSite(site: 'a', have: 1, expected: 2), ImageSite(site: 'b', have: 2, expected: 2)]);
    expect(p.percent, 50);
    expect(p.shortSites.map((s) => s.site), ['a']);
    expect(const ImageProgress(have: 0, want: 0, mb: 0, done: true).percent, 0);
  });

  test('only a task that mentions the hero-image job gets the card', () {
    expect(mentionsHeroImages({'links': ['docs/hero-images/index.md']}), isTrue);
    expect(mentionsHeroImages({'title': 'Write the report'}), isFalse);
  });

  testWidgets('the binder lists episodes, compiles the one tapped, and copies only on a tap', (t) async {
    final api = _FakeQuill();
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copied = (c.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpIn(t, BinderTab(api: api));
    expect(find.byKey(const Key('episode-07')), findsOneWidget);
    expect(find.text('v1.2 · 2026-10-01'), findsOneWidget);
    expect(api.calls, isEmpty, reason: 'nothing compiles until an episode is tapped');
    await t.tap(find.byKey(const Key('episode-07')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(api.calls, ['compile:it7']);
    expect(find.textContaining('decided before they start'), findsOneWidget);
    expect(copied, isNull);
    await t.tap(find.byKey(const Key('binder-copy')));
    await t.pump();
    expect(copied, 'Most vendor calls are decided before they start.');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('Draft sends the tone and the prompt; the result is a proposal, used or dropped on a tap', (t) async {
    final api = _FakeQuill();
    await pumpIn(t, ArticleAiScreen(title: 'My article', file: 'a.md', api: api, docs: _FakeDocs()));
    expect(find.text('The original article text.'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('article-words'))).data, startsWith('4 words'));
    await t.tap(find.byKey(const Key('article-tone')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Tone: Technical deep-dive').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const Key('article-polish')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(api.calls, ['polish:technical:']);
    expect(find.byKey(const Key('article-proposal')), findsOneWidget);
    expect(find.text('The original article text.'), findsOneWidget, reason: 'the working text is untouched until accepted');
    await t.tap(find.byKey(const Key('article-use')));
    await t.pump();
    expect(find.text('REWRITTEN: The original article text.'), findsOneWidget);
    expect(find.byKey(const Key('article-proposal')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a hub that does not serve article AI says so in words', (t) async {
    final api = _FakeQuill()..generateError = ApiException(404, 'Not found');
    await pumpIn(t, ArticleAiScreen(title: 'My article', file: 'a.md', api: api, docs: _FakeDocs()));
    await t.tap(find.byKey(const Key('article-draft')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('This hub does not serve that yet.'), findsOneWidget);
    expect(find.byKey(const Key('article-proposal')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('the image card shows the count and what is short, polls while running, and packages on a tap', (t) async {
    final api = _FakeQuill();
    final saved = <String>[];
    await pumpIn(t, ImageProgressCard(api: api, docs: _FakeDocs(), every: const Duration(seconds: 20), save: (n, b) async {
      saved.add('$n:${b.length}');
      return true;
    }));
    expect(find.textContaining('30 of 60 verified on disk - fleets running'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('image-percent'))).data, '50% · 12.5 MB');
    expect(find.text('still sourcing: alpha (10 short)'), findsOneWidget);
    expect(api.progressCalls, 1);
    await t.pump(const Duration(seconds: 21));
    expect(api.progressCalls, 2, reason: 'polled again after 20 s');
    await t.tap(find.byKey(const Key('image-package')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(api.calls, ['package']);
    expect(saved, ['hero-images.zip:3']);
    // Once the job is done the polling stops and the button goes.
    api.progress = const ImageProgress(have: 60, want: 60, mb: 20, done: true);
    await t.pump(const Duration(seconds: 21));
    expect(find.byKey(const Key('image-package')), findsNothing);
    final n = api.progressCalls;
    await t.pump(const Duration(seconds: 60));
    expect(api.progressCalls, n, reason: 'no more polling when done');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('with no progress source the card stays away', (t) async {
    final api = _FakeQuill();
    await pumpIn(t, ImageProgressCard(api: _Gone(api), docs: _FakeDocs()));
    expect(find.byKey(const Key('image-progress')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}

class _Gone extends _FakeQuill {
  _Gone(_FakeQuill _);
  @override
  Future<ImageProgress> imageProgress() async => throw ApiException(404, 'Not found');
}
