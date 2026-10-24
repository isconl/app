import '../api/client.dart';
import '../util/fmt.dart' as fmt;

/// BI26101515: the last hub routes the console has and the app lacked, behind one class that alone knows them.
/// Dropped after checking the console's call sites: none (every route below is still called by app.js).
///
/// Nothing here deletes, sends or changes a PIN on its own: the screens ask first (a delete names what goes, a send
/// shows the recipient and subject), and no token, code or PIN is ever logged or kept after the call returns.

/// The device-code style Google sign-in: show [userCode] and [verificationUri], then poll until connected.
class GoogleDeviceCode {
  const GoogleDeviceCode({required this.userCode, required this.verificationUri, required this.deviceCode, this.pollIntervalSec = 5});
  final String userCode, verificationUri, deviceCode;
  final int pollIntervalSec;
}

enum GooglePollState { waiting, connected, failed }

class GooglePoll {
  const GooglePoll(this.state, [this.error = '']);
  final GooglePollState state;
  final String error;
}

/// A mail the app is about to send. The screen shows [to] and [subject] before the explicit tap.
class GoogleDraft {
  const GoogleDraft({required this.to, required this.subject, required this.body, this.personId = ''});
  final String to, subject, body, personId;
}

class SpacesDrift {
  const SpacesDrift({required this.walked, this.missingLocally = const [], this.goneRemotely = const []});
  final int walked;
  final List<String> missingLocally, goneRemotely;
  bool get inSync => missingLocally.isEmpty && goneRemotely.isEmpty;

  String get line {
    if (inSync) return 'Registry matches OneDrive across $walked folders.';
    final parts = [
      if (missingLocally.isNotEmpty) '${missingLocally.length} folder(s) not in the registry',
      if (goneRemotely.isNotEmpty) '${goneRemotely.length} registered space(s) with no folder',
    ];
    return 'Drift: ${parts.join('; ')}.';
  }
}

class PinCheck {
  const PinCheck({required this.ok, this.error = '', this.attemptsLeft, this.lockedOut = false});
  final bool ok, lockedOut;
  final String error;
  final int? attemptsLeft;

  /// The sentence shown after a wrong PIN, with how many tries are left.
  String get message {
    if (ok) return 'PIN is right.';
    final left = attemptsLeft != null && !lockedOut ? ' $attemptsLeft ${attemptsLeft == 1 ? 'try' : 'tries'} left.' : '';
    return '${error.isEmpty ? 'Incorrect PIN.' : error}$left';
  }
}

/// 4 to 12 digits, as the console's own rule says.
String? pinProblem(String pin, String confirm) {
  if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) return 'PIN must be 4-12 digits.';
  if (pin != confirm) return 'PINs do not match.';
  return null;
}

/// The recipient and subject a person sees before Google send, in one block.
String googleSendPreview(GoogleDraft d) => 'To: ${d.to}\nSubject: ${d.subject.isEmpty ? '(no subject)' : d.subject}';

class ChatExport {
  const ChatExport({required this.content, required this.filename});
  final String content, filename;
}

class InboxIdentity {
  const InboxIdentity({required this.label, this.kind = '', this.person = ''});
  final String label, kind, person;
}

class PersonaSplit {
  const PersonaSplit({required this.day, this.lines = const [], this.error = ''});
  final String day, error;

  /// Each entry is a ready sentence, built from whatever the hub returned.
  final List<String> lines;
}

class VoiceCard {
  const VoiceCard({this.lines = const [], this.error = ''});
  final List<String> lines;
  final String error;
}

abstract class Parity9cApi {
  Future<ChatExport> exportThread();
  Future<void> deleteThread(String id);

  Future<GoogleDeviceCode> googleStart(String account);
  Future<GooglePoll> googlePoll(String account, String deviceCode);
  Future<void> googleSend(GoogleDraft draft);

  Future<void> inboxBackfill();
  Future<bool> inboxDelete(String id);
  Future<List<InboxIdentity>> inboxIdentities();

  Future<void> setProjectUrl(String id, String url);
  Future<SpacesDrift> spacesCheck();
  Future<PersonaSplit> personaSplit({String? day});
  Future<VoiceCard> voiceCard();

  Future<bool> pinIsSet();
  Future<void> setPin(String pin);
  Future<PinCheck> verifyPin(String pin);
}

class Parity9cException implements Exception {
  const Parity9cException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HttpParity9cApi implements Parity9cApi {
  HttpParity9cApi(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      return fmt.m(await api.postJson(path, body));
    } on ApiException catch (e) {
      throw Parity9cException(e.message);
    } on OfflineException {
      throw const Parity9cException('Offline.');
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      return fmt.m(await api.getJson(path));
    } on ApiException catch (e) {
      throw Parity9cException(e.message);
    } on OfflineException {
      throw const Parity9cException('Offline.');
    }
  }

  static void _ok(Map<String, dynamic> d, {String fallback = 'Refused.'}) {
    final good = d['success'] == true || d['ok'] == true;
    if (!good) throw Parity9cException(fmt.s(d['error']).isEmpty ? fallback : fmt.s(d['error']));
  }

  @override
  Future<ChatExport> exportThread() async {
    final d = await _post('/api/chat/export', {'format': 'md'});
    _ok(d);
    return ChatExport(content: fmt.s(d['content']), filename: fmt.s(d['filename']).isEmpty ? 'chat.md' : fmt.s(d['filename']));
  }

  @override
  Future<void> deleteThread(String id) async => _post('/api/chat/thread/delete', {'id': id});

  @override
  Future<GoogleDeviceCode> googleStart(String account) async {
    final d = await _post('/api/google/auth/start', {'account': account});
    _ok(d, fallback: 'Google did not give a code.');
    return GoogleDeviceCode(
      userCode: fmt.s(d['userCode']),
      verificationUri: fmt.s(d['verificationUri']),
      deviceCode: fmt.s(d['deviceCode']),
      pollIntervalSec: fmt.i(d['pollIntervalSec'], 5).clamp(2, 60),
    );
  }

  @override
  Future<GooglePoll> googlePoll(String account, String deviceCode) async {
    final d = await _post('/api/google/auth/poll', {'account': account, 'deviceCode': deviceCode});
    if (d['connected'] == true) return const GooglePoll(GooglePollState.connected);
    if (d['waiting'] == true) return const GooglePoll(GooglePollState.waiting);
    return GooglePoll(GooglePollState.failed, fmt.s(d['error']).isEmpty ? 'sign-in did not complete' : fmt.s(d['error']));
  }

  @override
  Future<void> googleSend(GoogleDraft draft) async {
    final d = await _post('/api/google/send', {'to': draft.to, 'subject': draft.subject, 'body': draft.body, if (draft.personId.isNotEmpty) 'personId': draft.personId});
    _ok(d, fallback: 'unknown error');
  }

  @override
  Future<void> inboxBackfill() async {
    final d = await _post('/api/inbox/backfill', {});
    if (fmt.s(d['error']).isNotEmpty) throw Parity9cException(fmt.s(d['error']));
  }

  @override
  Future<bool> inboxDelete(String id) async => (await _post('/api/inbox/delete', {'id': id}))['success'] == true;

  @override
  Future<List<InboxIdentity>> inboxIdentities() async => [
        for (final m in fmt.lm((await _get('/api/inbox/identities'))['identities']))
          InboxIdentity(
            label: [fmt.s(m['value']), fmt.s(m['address']), fmt.s(m['id']), fmt.s(m['NAME'])].firstWhere((s) => s.isNotEmpty, orElse: () => ''),
            kind: fmt.s(m['kind']),
            person: [fmt.s(m['person']), fmt.s(m['personName'])].firstWhere((s) => s.isNotEmpty, orElse: () => ''),
          ),
      ];

  @override
  Future<void> setProjectUrl(String id, String url) async => _ok(await _post('/api/projects/url', {'id': id, 'url': url}));

  @override
  Future<SpacesDrift> spacesCheck() async {
    final d = await _post('/api/spaces/sync', {'apply': false});
    _ok(d, fallback: 'Sync check failed');
    return SpacesDrift(
      walked: fmt.i(d['walked']),
      missingLocally: [for (final x in fmt.l(d['missingLocally'])) '$x'],
      goneRemotely: [for (final x in fmt.l(d['goneRemotely'])) '$x'],
    );
  }

  @override
  Future<PersonaSplit> personaSplit({String? day}) async {
    final d = await _get('/api/identity/persona-split${day == null || day.isEmpty ? '' : '?day=${Uri.encodeQueryComponent(day)}'}');
    if (fmt.s(d['error']).isNotEmpty) return PersonaSplit(day: day ?? '', error: fmt.s(d['error']));
    return PersonaSplit(day: fmt.s(d['day']).isEmpty ? (day ?? '') : fmt.s(d['day']), lines: _lines(d, skip: const {'day', 'success', 'ok'}));
  }

  @override
  Future<VoiceCard> voiceCard() async {
    try {
      final d = await _get('/api/voice/card');
      if (fmt.s(d['error']).isNotEmpty) return VoiceCard(error: fmt.s(d['error']));
      return VoiceCard(lines: _lines(d, skip: const {'success', 'ok'}));
    } on Parity9cException catch (e) {
      return VoiceCard(error: e.message);
    }
  }

  /// Turns a hub object into display sentences without guessing its shape: scalars as `key: value`, lists of text as
  /// one line each. Nested maps are summarised by key and size.
  static List<String> _lines(Map<String, dynamic> d, {Set<String> skip = const {}}) {
    final out = <String>[];
    d.forEach((k, v) {
      if (skip.contains(k) || v == null) return;
      if (v is String && v.isNotEmpty) out.add('$k: $v');
      if (v is num || v is bool) out.add('$k: $v');
      if (v is List) {
        final texts = [for (final x in v) if (x is String && x.isNotEmpty) x];
        if (texts.isNotEmpty) {
          out.addAll(texts);
        } else if (v.isNotEmpty) {
          out.add('$k: ${v.length} items');
        }
      }
      if (v is Map && v.isNotEmpty) out.add('$k: ${v.length} entries');
    });
    return out;
  }

  @override
  Future<bool> pinIsSet() async => (await _get('/api/auth/methods'))['pin'] == true;

  @override
  Future<void> setPin(String pin) async => _ok(await _post('/api/auth/set-pin', {'pin': pin}), fallback: 'Could not set the PIN.');

  @override
  Future<PinCheck> verifyPin(String pin) async {
    try {
      final d = await _post('/api/auth/pin', {'pin': pin});
      return PinCheck(ok: d['success'] == true, error: fmt.s(d['error']), attemptsLeft: d['attemptsLeft'] is num ? (d['attemptsLeft'] as num).toInt() : null, lockedOut: d['lockedOut'] == true);
    } on Parity9cException catch (e) {
      return PinCheck(ok: false, error: e.message);
    }
  }
}
