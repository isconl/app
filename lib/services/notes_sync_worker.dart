import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:workmanager/workmanager.dart';

import '../api/client.dart';
import '../data/db.dart';
import '../data/outbox.dart';
import 'prefetch_worker.dart' show prefetchDispatcher;
import 'session.dart';

/// BI26112302 (Sconl, study note: "whenever the phone has internet access, the sync must be started automatically even
/// without me opening the app, or even clicking sync now"): notes and every other queued write leave the phone through
/// Android WorkManager the moment a network is there, app open or not.
///
/// Two registrations share one task: a periodic one every 15 minutes (Android's minimum) that runs only with a network,
/// and a one-off "as soon as there is a network" request made whenever a note is saved but could not be sent. Android
/// holds both until the phone is online, survives reboots, and retries on its own schedule.
const notesSyncUniqueName = 'isconl.notessync.periodic';
const notesSyncOnceName = 'isconl.notessync.once';
const notesSyncTaskName = 'isconl.notessync';

bool get _supported => !kIsWeb && Platform.isAndroid;

/// The background entry: its own database and session, every unsent note posted, then the outbox drained.
Future<bool> runNotesSyncBackground() async {
  try {
    final db = await AppDb.open();
    final session = SessionService();
    await session.load();
    ApiClient apiOf() => session.api;
    for (final row in await db.unsyncedLessonNotes()) {
      final text = row['text'] as String? ?? '';
      if (text.trim().isEmpty && row['synced_at'] == null) continue;
      final version = row['updated_at'] as int;
      final course = row['course'] as String;
      final file = row['file'] as String;
      try {
        // BI26112340: annotations on slate docs go to slate, beside the doc; module notes go to spark.
        if (course.startsWith('slate:')) {
          await apiOf().postJson('/api/slate/docs/${Uri.encodeComponent('NOTES.$file')}', {'text': text});
        } else {
          await apiOf().postJson('/api/learning/notes', {'course': course, 'file': file, 'text': text});
        }
        await db.markLessonNoteSynced(course: course, file: file, version: version);
      } on OfflineException {
        break; // no network after all: Android runs the task again when there is one
      } catch (_) {
        // A refusal for one note does not hold back the others; the app shows it in the notes view.
      }
    }
    await OutboxService(db, apiOf).drain();
  } catch (_) {
    // Swallowed on purpose, as in the prefetch task: the next run tries again.
  }
  return true;
}

/// Registers the periodic network-only sync. Call once at start.
Future<void> syncNotesSchedule() async {
  if (!_supported) return;
  try {
    final wm = Workmanager();
    await wm.initialize(prefetchDispatcher);
    await wm.registerPeriodicTask(
      notesSyncUniqueName,
      notesSyncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {
    // No WorkManager (tests, desktop): the foreground sync still runs.
  }
}

/// Asks Android to run the sync as soon as a network is there. Call after a note is saved but not yet sent.
Future<void> requestNotesSyncSoon() async {
  if (!_supported) return;
  try {
    await Workmanager().registerOneOffTask(
      notesSyncOnceName,
      notesSyncTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (_) {}
}
