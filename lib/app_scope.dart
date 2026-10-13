import 'package:flutter/widgets.dart';

import 'api/client.dart';
import 'data/db.dart';
import 'data/lesson_notes.dart';
import 'data/modules.dart';
import 'data/mutations.dart';
import 'data/outbox.dart';
import 'data/store.dart';
import 'data/sync.dart';
import 'services/narration.dart';
import 'services/session.dart';
import 'services/sms_ingest.dart';
import 'services/updater.dart';

/// Composition root: one instance of every service, built in main().
class AppServices {
  AppServices._({
    required this.db,
    required this.session,
    required this.store,
    required this.modules,
    required this.narrator,
    required this.sms,
    required this.outbox,
    required this.sync,
    required this.mutations,
    required this.updater,
    required this.lessonNotes,
  });

  @visibleForTesting
  factory AppServices.forTesting({
    required AppDb db,
    required SessionService session,
    required Store store,
    required ModuleLibrary modules,
    required Narrator narrator,
    required SmsIngest sms,
    required OutboxService outbox,
    required SyncEngine sync,
    required Mutations mutations,
    required UpdateService updater,
    required LessonNotesRepository lessonNotes,
  }) =>
      AppServices._(
        db: db,
        session: session,
        store: store,
        modules: modules,
        narrator: narrator,
        sms: sms,
        outbox: outbox,
        sync: sync,
        mutations: mutations,
        updater: updater,
        lessonNotes: lessonNotes,
      );

  final AppDb db;
  final SessionService session;
  final Store store;

  /// The local module library. Downloaded modules stay downloaded until their
  /// content changes - see lib/data/modules.dart.
  final ModuleLibrary modules;

  /// Course audio: the device voice by default, the agent's narration on
  /// request. See services/narration.dart.
  final Narrator narrator;

  /// Automatic M-Pesa context from his SMS. See services/sms_ingest.dart.
  final SmsIngest sms;
  final OutboxService outbox;
  final SyncEngine sync;
  final Mutations mutations;
  final UpdateService updater;

  /// Isolated lesson notes storage (Study-on-Canvas contract).
  final LessonNotesRepository lessonNotes;

  ApiClient get api => session.api;

  static Future<AppServices> boot() async {
    final db = await AppDb.open();
    final session = SessionService();
    await session.load();
    ApiClient apiOf() => session.api;
    final store = Store(db, apiOf);
    final outbox = OutboxService(db, apiOf);
    final sync = SyncEngine(store, outbox, apiOf);
    final mutations = Mutations(store, outbox, sync, apiOf, db);
    final modules = ModuleLibrary(db, store, apiOf);
    final narrator = Narrator(apiOf)
      // BI26101394: the place in each module and the chosen device voice survive a restart.
      ..readSetting = (k) async {
        final v = (await db.getSnapshot(k))?.$1;
        return v is String ? v : null;
      }
      ..writeSetting = (k, v) => v == null ? db.deleteSnapshot(k) : db.putSnapshot(k, v);
    final sms = SmsIngest(apiOf);
    final updater = UpdateService(apiOf);
    final lessonNotes = LessonNotesRepository(apiOf: apiOf, mutations: mutations, db: db);
    await outbox.refreshCount();
    await modules.load();
    await updater.loadInstalled();
    return AppServices._(
      db: db,
      session: session,
      store: store,
      modules: modules,
      narrator: narrator,
      sms: sms,
      outbox: outbox,
      sync: sync,
      mutations: mutations,
      updater: updater,
      lessonNotes: lessonNotes,
    );
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppScope>()!
      .services;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      services != oldWidget.services;
}
