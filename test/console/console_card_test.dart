import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/console/console_mode.dart';
import 'package:isconl/console/console_player.dart';
import 'package:isconl/console/console_recorder.dart';
import 'package:isconl/console/console_services.dart';
import 'package:isconl/ui/widgets/console_faces.dart';
import 'package:isconl/ui/widgets/context_ring_card.dart';

import 'fakes.dart';
import 'test_services.dart';

/// BI26092648: the Console card's three faces, driven the way a thumb drives them.
void main() {
  setUpAll(initSqfliteForTests);

  group('the card', () {
    testWidgets('a double-tap cycles Progress, Player, Recorder and back, and the mode is remembered', (tester) async {
      final services = (await tester.runAsync(() => buildTestServices()))!;
      await tester.pumpWidget(AppScope(
        services: services,
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ContextRingCard()))),
      ));
      await tester.pump();

      Text pill() => tester.widget<Text>(find.byKey(const ValueKey('console-pill')));
      expect(pill().data, 'Console');
      for (final m in ConsoleMode.values) {
        expect(find.byKey(ValueKey('console-dot-${m.name}')), findsOneWidget);
      }

      Future<void> doubleTap() async {
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byKey(const ValueKey('console-pill')));
          await tester.pump(const Duration(milliseconds: 80));
        }
        await tester.pump(const Duration(milliseconds: 250));
      }

      await doubleTap();
      expect(pill().data, 'Console · Player');
      expect(find.text('Nothing queued'), findsOneWidget);
      await doubleTap();
      expect(pill().data, 'Console · Recorder');
      expect(find.text('READY'), findsOneWidget);
      await doubleTap();
      expect(pill().data, 'Console');

      // One tap is not enough.
      await tester.tap(find.byKey(const ValueKey('console-pill')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(pill().data, 'Console');

      // Remembered: a new card on the same app opens on the last mode.
      await doubleTap();
      expect(pill().data, 'Console · Player');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(AppScope(
        services: services,
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ContextRingCard()))),
      ));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(pill().data, 'Console · Player');
    });
  });

  group('Player face', () {
    late FakeAudio audio;
    late ConsolePlayer player;
    late ConsoleServices console;

    Future<void> pumpPlayer(WidgetTester tester) async {
      audio = FakeAudio();
      final kv = MemoryKv();
      player = ConsolePlayer(() => audio, kv);
      final mic = FakeMic();
      console = ConsoleServices.forTesting(
        mode: ConsoleModeController(kv),
        player: player,
        recorder: makeRecorder(mic: mic, clock: Clock(), kv: kv, uploads: []),
        store: kv,
      );
      await tester.runAsync(() => player.addToQueue(const ConsoleTrack(id: 'a', title: 'A long module narration', uri: 'https://x/a')));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: PlayerFace(player: player, services: console))),
      ));
      await tester.pump();
    }

    testWidgets('shows the title, the time and the speed, and the centre plays and pauses', (tester) async {
      await pumpPlayer(tester);
      expect(find.text('A long module narration'), findsOneWidget);
      expect(find.text('00:00 / 10:00'), findsOneWidget);
      expect(find.text('1×'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('console-player-play')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(audio.isPlaying, isTrue);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('skip buttons move 15 s back and 30 s forward', (tester) async {
      await pumpPlayer(tester);
      await tester.runAsync(() async {
        audio.pos.add(const Duration(minutes: 2));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('console-player-forward')));
      await tester.pump();
      expect(audio.seeks.last, const Duration(minutes: 2, seconds: 30));
      await tester.tap(find.byKey(const ValueKey('console-player-back')));
      await tester.pump();
      expect(audio.seeks.last, const Duration(minutes: 2, seconds: 15));
    });

    testWidgets('the speed chip cycles through the four speeds', (tester) async {
      await pumpPlayer(tester);
      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('console-player-speed')));
        await tester.pump();
        seen.add(tester.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('console-player-speed')), matching: find.byType(Text))).single.data!);
      }
      expect(seen, ['1.25×', '1.5×', '2×', '1×']);
    });

    testWidgets('a drag along the ring scrubs proportionally', (tester) async {
      await pumpPlayer(tester);
      final ring = find.byKey(const ValueKey('console-scrub-ring'));
      final origin = tester.getTopLeft(ring);
      // Start at 3 o'clock on the ring's band and sweep clockwise to 6 o'clock.
      final g = await tester.startGesture(origin + const Offset(160, 85));
      await g.moveBy(const Offset(0, 30));
      await g.moveTo(origin + const Offset(85, 160));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(audio.seeks, isNotEmpty);
      expect(audio.seeks.last.inSeconds, closeTo(300, 1), reason: 'half a lap is half the track');
    });

    testWidgets('a touch in the middle, off the ring, does not scrub', (tester) async {
      await pumpPlayer(tester);
      final ring = find.byKey(const ValueKey('console-scrub-ring'));
      final origin = tester.getTopLeft(ring);
      final g = await tester.startGesture(origin + const Offset(85, 60));
      await g.moveBy(const Offset(0, 30));
      await g.moveBy(const Offset(10, 10));
      await g.up();
      await tester.pump();
      expect(audio.seeks, isEmpty);
    });

    testWidgets('the queue sheet lists the queue', (tester) async {
      await pumpPlayer(tester);
      final services = (await tester.runAsync(() => buildTestServices()))!;
      await tester.pumpWidget(AppScope(
        services: services,
        child: MaterialApp(home: Scaffold(body: Center(child: PlayerFace(player: player, services: console)))),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('console-player-queue')));
      await tester.pumpAndSettle();
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('A long module narration'), findsWidgets);
    });
  });

  group('Recorder face', () {
    late FakeMic mic;
    late Clock clock;
    late MemoryKv kv;
    late List<Upload> uploads;
    late ConsoleRecorder recorder;
    late ConsoleServices console;

    Future<void> pumpRecorder(WidgetTester tester, {bool explain = false, Future<bool> Function(BuildContext)? explainMic}) async {
      mic = FakeMic();
      clock = Clock();
      kv = MemoryKv();
      uploads = [];
      if (!explain) kv.data['console.mic_explained'] = 'yes';
      recorder = makeRecorder(mic: mic, clock: clock, kv: kv, uploads: uploads, bytes: Uint8List.fromList([1, 2, 3]));
      console = ConsoleServices.forTesting(
        mode: ConsoleModeController(kv),
        player: ConsolePlayer(() => FakeAudio(), kv),
        recorder: recorder,
        store: kv,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: RecorderFace(recorder: recorder, services: console, explainMic: explainMic))),
      ));
      await tester.pump();
    }

    testWidgets('record shows a stop square, REC and the clock; stop shows Keep and Discard', (tester) async {
      await pumpRecorder(tester);
      expect(find.text('READY'), findsOneWidget);
      expect(find.byKey(const ValueKey('console-record-glyph')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byKey(const ValueKey('console-stop-glyph')), findsOneWidget, reason: 'the stop button appears while recording');
      clock.advance(const Duration(seconds: 192));
      recorder.tick();
      await tester.pump();
      expect(find.text('REC 03:12'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('TAKE 03:12'), findsOneWidget);
      expect(find.byKey(const ValueKey('console-rec-keep')), findsOneWidget);
      expect(find.byKey(const ValueKey('console-rec-discard')), findsOneWidget);
      expect(uploads, isEmpty);
    });

    testWidgets('Keep with a title queues the upload and shows where the take is', (tester) async {
      await pumpRecorder(tester);
      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('console-rec-title')), 'Site visit');
      await tester.tap(find.byKey(const ValueKey('console-rec-keep')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(uploads, hasLength(1), reason: 'offline recording queues an upload');
      expect(uploads.single.body['title'], 'Site visit');
      expect(find.byKey(const ValueKey('console-rec-status')), findsOneWidget);
      expect(find.text('READY'), findsOneWidget);
    });

    testWidgets('long-press pauses and resumes', (tester) async {
      await pumpRecorder(tester);
      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.longPress(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(recorder.state, RecorderState.paused);
      expect(find.textContaining('PAUSED'), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(recorder.state, RecorderState.recording);
      await tester.runAsync(recorder.discard);
      await tester.pump();
    });

    testWidgets('the first record explains the microphone; declining records nothing', (tester) async {
      var asked = 0;
      await pumpRecorder(tester, explain: true, explainMic: (_) async {
        asked++;
        return false;
      });
      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(asked, 1);
      expect(recorder.state, RecorderState.idle);
      expect(mic.started, isFalse);
      expect(kv.data['console.mic_explained'], isNull);
    });

    testWidgets('accepting the explanation records, and it is not asked again', (tester) async {
      var asked = 0;
      await pumpRecorder(tester, explain: true, explainMic: (_) async {
        asked++;
        return true;
      });
      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      expect(recorder.state, RecorderState.recording);
      expect(kv.data['console.mic_explained'], 'yes');
      await tester.tap(find.byKey(const ValueKey('console-record'))); // stop
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await recorder.discard();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(asked, 1);
      await tester.runAsync(recorder.discard);
      await tester.pump();
    });

    testWidgets('a refused microphone shows a sentence', (tester) async {
      await pumpRecorder(tester);
      mic.allowed = false;
      await tester.tap(find.byKey(const ValueKey('console-record')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byKey(const ValueKey('console-rec-error')), findsOneWidget);
      expect(recorder.state, RecorderState.idle);
    });
  });
}
