import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// The Cover tab of the chat sheet (BI26092642): person-to-person conversations through the Cover engine, beside the agent chat.
/// Hub answers `/api/cover/*`; Cover is not deployed yet, so the pane first asks whether it is connected and says so plainly when
/// it is not (a 200 with `connected: false`, never an error). A call button is present but disabled until the call stack ships.
/// Bubbles follow the Inbox conversation style: own messages on the right, a time on every bubble, day separators.

/// `HH:MM` from an ISO time, or empty.
String coverTime(String iso) {
  final m = RegExp(r'T(\d{2}:\d{2})').firstMatch(iso);
  return m == null ? '' : m.group(1)!;
}

String coverDay(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

class CoverPane extends StatefulWidget {
  const CoverPane({super.key});

  @override
  State<CoverPane> createState() => _CoverPaneState();
}

class _CoverPaneState extends State<CoverPane> {
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _threads = const [];
  Map<String, dynamic>? _open;
  List<Map<String, dynamic>>? _messages;
  String _error = '';
  bool _sending = false;
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status == null) _load();
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    Map<String, dynamic> status;
    try {
      status = fmt.m(await api.getJson('/api/cover/status'));
    } catch (_) {
      status = {'connected': false, 'reason': 'The console did not answer.'};
    }
    var threads = <Map<String, dynamic>>[];
    var error = '';
    if (status['connected'] == true) {
      try {
        final t = fmt.m(await api.getJson('/api/cover/threads'));
        threads = fmt.lm(t['threads']).map(fmt.m).toList();
        if (t['ok'] != true) error = fmt.s(t['reason']);
      } catch (_) {
        error = 'Conversations could not be read.';
      }
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _threads = threads;
      _error = error;
    });
  }

  Future<void> _openThread(Map<String, dynamic> t) async {
    setState(() {
      _open = t;
      _messages = null;
    });
    final api = AppScope.of(context).api;
    try {
      final r = fmt.m(await api.getJson('/api/cover/messages?thread=${Uri.encodeQueryComponent(fmt.s(t['id']))}'));
      if (!mounted) return;
      setState(() {
        _messages = fmt.lm(r['messages']).map(fmt.m).toList();
        _error = r['ok'] == true ? '' : fmt.s(r['reason']);
      });
    } catch (_) {
      if (mounted) setState(() => _messages = const []);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _open == null || _sending) return;
    final api = AppScope.of(context).api;
    setState(() => _sending = true);
    try {
      final r = fmt.m(await api.postJson('/api/cover/send', {'thread': fmt.s(_open!['id']), 'text': text}));
      if (r['ok'] == true) {
        _input.clear();
        if (mounted) await _openThread(_open!);
      } else if (mounted) {
        setState(() => _error = fmt.s(r['reason']).isEmpty ? 'The message was not sent.' : fmt.s(r['reason']));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The message was not sent.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) return const Center(child: MiniSpinner(size: 20));
    if (s['connected'] != true) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Cover isn't connected.", key: const Key('cover-off'), style: T.title),
            const SizedBox(height: 8),
            Text(
              '${fmt.s(s['reason'])} Private conversations and calls appear here once the Cover engine is running and this app is pointed at it. The agent chat is not affected.',
              style: T.small.copyWith(color: C.text3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            TextButton(key: const Key('cover-retry'), onPressed: () {
              setState(() => _status = null);
              _load();
            }, child: const Text('Check again')),
          ],
        ),
      );
    }
    final t = _open;
    if (t == null) return _list();
    return _thread(t);
  }

  Widget _list() {
    if (_threads.isEmpty) {
      return const EmptyState('No conversations yet', 'Private conversations with people appear here.', icon: Icons.forum_rounded);
    }
    return ListView(
      children: [
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(_error, style: T.tiny.copyWith(color: C.amber))),
        for (final t in _threads)
          ListTile(
            key: Key('cover-thread-${fmt.s(t['id'])}'),
            onTap: () => _openThread(t),
            title: Text(fmt.s(t['name']), style: T.body2),
            subtitle: Text('${fmt.m(t['last'])['own'] == true ? 'You: ' : ''}${fmt.s(fmt.m(t['last'])['text'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny.copyWith(color: C.text3)),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(coverTime(fmt.s(fmt.m(t['last'])['at'])), style: T.monoSmall.copyWith(color: C.text3)),
              if (fmt.d(t['unread']).toInt() > 0) Badge2('${fmt.d(t['unread']).toInt()}', color: C.greenBg, textColor: C.greenBright),
            ]),
          ),
      ],
    );
  }

  Widget _thread(Map<String, dynamic> t) {
    final msgs = _messages;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Row(children: [
            IconButton(key: const Key('cover-back'), icon: const Icon(Icons.arrow_back_rounded, size: 20), onPressed: () => setState(() {
              _open = null;
              _messages = null;
            })),
            Expanded(child: Text(fmt.s(t['name']), style: T.title)),
            const Tooltip(message: 'calls coming', child: IconButton(key: Key('cover-voice'), onPressed: null, icon: Icon(Icons.call_rounded, size: 20))),
            const Tooltip(message: 'calls coming', child: IconButton(key: Key('cover-video'), onPressed: null, icon: Icon(Icons.videocam_rounded, size: 20))),
          ]),
        ),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text(_error, key: const Key('cover-error'), style: T.tiny.copyWith(color: C.amber))),
        const Divider(height: 1),
        Expanded(
          child: msgs == null
              ? const Center(child: MiniSpinner(size: 20))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (var i = 0; i < msgs.length; i++) ...[
                    if (i == 0 || coverDay(fmt.s(msgs[i - 1]['at'])) != coverDay(fmt.s(msgs[i]['at'])))
                      Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(coverDay(fmt.s(msgs[i]['at'])), style: T.tiny.copyWith(color: C.text3)))),
                    _bubble(msgs[i]),
                  ],
                ]),
        ),
        Container(
          padding: EdgeInsets.only(left: 14, right: 14, top: 8, bottom: 10 + MediaQuery.of(context).viewInsets.bottom),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border))),
          child: Row(children: [
            Expanded(child: TextField(key: const Key('cover-input'), controller: _input, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Message'))),
            const SizedBox(width: 8),
            FilledButton(key: const Key('cover-send'), onPressed: _sending ? null : _send, child: const Icon(Icons.arrow_upward_rounded, size: 18)),
          ]),
        ),
      ],
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final own = m['own'] == true;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: Key('cover-msg-${fmt.s(m['id'])}-${own ? 'out' : 'in'}'),
        margin: const EdgeInsets.only(bottom: 8, left: 40, right: 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: own ? C.greenBg : C.surface,
          border: Border.all(color: own ? C.green : C.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(coverTime(fmt.s(m['at'])), style: T.monoSmall.copyWith(color: C.text3)),
          Text(fmt.s(m['text']), style: T.small),
        ]),
      ),
    );
  }
}
