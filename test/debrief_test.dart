import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/api/client.dart';
import 'package:isconl/console/console_recorder.dart' show RecorderBackend;
import 'package:isconl/services/debrief.dart';
import 'package:isconl/ui/widgets/debrief_card.dart';

class FakeRecorder implements RecorderBackend {
  bool allowed = true;
  bool started = false;
  String? path;
  @override
  Future<bool> ensurePermission() async => allowed;
  @override
  Future<void> start(String p) async {
    started = true;
    path = p;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<String?> stop() async => path;
  @override
  Stream<double> get levelStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

class FakeApi implements DebriefApi {
  Object? transcribeError;
  Object? proposeError;
  bool keepSeen = false;
  final applied = <List<String>>[];
  final undone = <String>[];
  var json = <String, dynamic>{
    'close': [
      {'id': 'c1', 'title': 'Send the deck', 'evidence': 'sent the deck'}
    ],
    'notes': [
      {'id': 'n1', 'person': 'Amina', 'note': 'back from leave', 'evidence': 'spoke to Amina', 'candidates': [
        {'id': 'p1', 'label': 'Amina K'},
        {'id': 'p2', 'label': 'Amina W'},
      ]},
      {'id': 'n2', 'person': 'Zed', 'evidence': 'bumped into Zed', 'unknown': true},
    ],
    'tomorrow': [
      {'id': 't1', 'title': 'Call the bank'},
      {'id': 't2', 'title': 'Plan the week'},
      {'id': 't3', 'title': 'Gym'},
      {'id': 't4', 'title': 'Fourth is dropped'},
    ],
  };

  @override
  Future<String> transcribe(Uint8List audio, {required bool keepAudio}) async {
    keepSeen = keepAudio;
    if (transcribeError != null) throw transcribeError!;
    return 'I sent the deck and spoke to Amina.';
  }

  @override
  Future<DebriefProposal> propose(String transcript) async {
    if (proposeError != null) throw proposeError!;
    return DebriefProposal.parse(json);
  }

  @override
  Future<String> apply(List<DebriefItem> items, String transcript) async {
    applied.add([for (final i in items) i.id]);
    return 'a1';
  }

  @override
  Future<void> undo(String id) async => undone.add(id);
}

DebriefController make(FakeRecorder r, FakeApi a, {List<String>? deleted, DateTime? now}) => DebriefController(
      recorder: r,
      api: a,
      newPath: () async => '/tmp/d.m4a',
      readBytes: (_) async => Uint8List.fromList([1, 2, 3]),
      deleteFile: (p) async => deleted?.add(p),
      now: () => now ?? DateTime(2026, 10, 15, 19),
    );

void main() {
  test('parse: matched items are ticked, ambiguous and unknown are not, tomorrow keeps three', () {
    final p = DebriefProposal.parse(FakeApi().json);
    expect(p.of(DebriefGroup.close).single.ticked, true);
    final amina = p.of(DebriefGroup.notes).first;
    expect(amina.ambiguous, true);
    expect(amina.ticked, false);
    expect(amina.needsChoice, true);
    final zed = p.of(DebriefGroup.notes).last;
    expect(zed.unknownName, true);
    expect(zed.ticked, false);
    expect(p.of(DebriefGroup.tomorrow).length, 3);
    expect(p.ticked.map((i) => i.id), ['c1', 't1', 't2', 't3']);
  });

  test('the hour decides whether the debrief opens', () {
    final c = make(FakeRecorder(), FakeApi(), now: DateTime(2026, 10, 15, 17, 59));
    expect(c.isEvening, false);
    expect(make(FakeRecorder(), FakeApi(), now: DateTime(2026, 10, 15, 18)).isEvening, true);
  });

  test('a refused microphone says so and records nothing', () async {
    final r = FakeRecorder()..allowed = false;
    final c = make(r, FakeApi());
    await c.start();
    expect(c.phase, DebriefPhase.failed);
    expect(r.started, false);
    expect(c.message, contains('microphone'));
  });

  test('record, stop: transcript, proposal, the audio is deleted after upload, nothing applied yet', () async {
    final api = FakeApi();
    final deleted = <String>[];
    final c = make(FakeRecorder(), api, deleted: deleted);
    await c.start();
    expect(c.phase, DebriefPhase.recording);
    await c.stop();
    expect(c.phase, DebriefPhase.review);
    expect(c.transcript, contains('spoke to Amina'));
    expect(deleted, ['/tmp/d.m4a']);
    expect(api.applied, isEmpty);
    expect(api.keepSeen, false);
  });

  test('the clock turns amber at 60 s', () async {
    final c = make(FakeRecorder(), FakeApi());
    await c.start();
    c.elapsed = const Duration(seconds: 59);
    expect(c.amber, false);
    c.elapsed = const Duration(seconds: 60);
    expect(c.amber, true);
    c.dispose();
  });

  test('the cap stops the take by itself', () async {
    final c = DebriefController(
      recorder: FakeRecorder(),
      api: FakeApi(),
      newPath: () async => '/tmp/d.m4a',
      readBytes: (_) async => Uint8List.fromList([1]),
      deleteFile: (_) async {},
      cap: const Duration(seconds: 1),
    );
    await c.start();
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    expect(c.phase, DebriefPhase.review);
    c.dispose();
  });
  test('confirm applies only the ticked items; an ambiguous one needs a pick first; undo reverses', () async {
    final api = FakeApi();
    final c = make(FakeRecorder(), api);
    await c.start();
    await c.stop();
    final amina = c.proposal!.of(DebriefGroup.notes).first;
    c.toggle(amina);
    expect(amina.ticked, false, reason: 'cannot tick before choosing');
    c.choose(amina, amina.candidates.last);
    expect(amina.ticked, true);
    c.toggle(c.proposal!.of(DebriefGroup.tomorrow).last);
    await c.confirm();
    expect(c.phase, DebriefPhase.applied);
    expect(api.applied.single, ['c1', 'n1', 't1', 't2']);
    expect(c.undoLeft, 10);
    await c.undo();
    expect(api.undone, ['a1']);
    expect(c.phase, DebriefPhase.review);
    c.dispose();
  });

  test('offline: the recording is kept, nothing is applied, and a retry finishes it', () async {
    final api = FakeApi()..transcribeError = OfflineException();
    final deleted = <String>[];
    final c = make(FakeRecorder(), api, deleted: deleted);
    await c.start();
    await c.stop();
    expect(c.phase, DebriefPhase.queued);
    expect(c.hasQueued, true);
    expect(deleted, isEmpty);
    expect(api.applied, isEmpty);
    api.transcribeError = null;
    await c.retry();
    expect(c.phase, DebriefPhase.review);
    expect(c.hasQueued, false);
    expect(deleted, ['/tmp/d.m4a']);
  });

  test('a failed proposal keeps the transcript and can be retried', () async {
    final api = FakeApi()..proposeError = ApiException(0, 'Engine busy');
    final c = make(FakeRecorder(), api);
    await c.start();
    await c.stop();
    expect(c.phase, DebriefPhase.failed);
    expect(c.transcript, isNotEmpty);
    api.proposeError = null;
    await c.retryPropose();
    expect(c.phase, DebriefPhase.review);
  });

  testWidgets('the card: idle button, then recording shows the timer, then the proposal sheet with groups', (t) async {
    final c = make(FakeRecorder(), FakeApi());
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DebriefCard(controller: c, alwaysShow: true)))));
    expect(find.byKey(const Key('debrief-record')), findsOneWidget);
    await t.tap(find.byKey(const Key('debrief-record')));
    await t.pump();
    expect(find.byKey(const Key('debrief-timer')), findsOneWidget);
    await t.tap(find.byKey(const Key('debrief-record')));
    await t.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Circle notes'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('"sent the deck"'), findsOneWidget);
    expect(find.text('Add person? Zed'), findsOneWidget);
    expect(find.byKey(const Key('pick-n1')), findsOneWidget);
    await t.tap(find.byKey(const Key('proposal-confirm')));
    await t.pump();
    expect(find.byKey(const Key('debrief-undo')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
}
