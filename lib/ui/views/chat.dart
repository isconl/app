import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/markdown.dart';
import '../widgets/common.dart';

/// Full-height Ask sheet - talk to the agent.
/// Streaming over SSE; cloud providers answer in one lump (thinking shimmer),
/// the local model streams tokens (typewriter).
Future<void> openChatSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
      side: BorderSide(color: C.border),
    ),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.94,
      child: ChatSheet(),
    ),
  );
}

class ChatSheet extends StatefulWidget {
  const ChatSheet({super.key, this.embedded = false});

  /// True when hosted in the desktop [ChatRail] (a permanent column) rather
  /// than the mobile modal sheet - hides the close button, which has
  /// nothing to pop in that context.
  final bool embedded;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _Msg {
  _Msg(this.role, this.text, {this.pending = false});
  final String role; // user | agent | error
  String text;
  String via = '';
  bool pending;

  // Set when this message is an /api/act response awaiting the user's word:
  // [actionOptions] for an ambiguous-match disambiguation, [actionPlan] for
  // a gated action's yes/no. Cleared (both set null) once resolved, so the
  // card collapses to plain text the same way the legacy dashboard did.
  List<Map<String, String>>? actionOptions;
  Map<String, dynamic>? actionPlan;
  String? actionDescribe;
}

class _ChatSheetState extends State<ChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _busy = false;
  bool _loaded = false;

  static const _quickChips = [
    'What needs me today?',
    'Summarize my inbox',
    'What is overdue?',
    'Any risks tripping?',
    'Draft my day plan',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final services = AppScope.of(context);
    final rows = await services.db.chatHistory();
    if (!mounted) return;
    setState(() {
      _messages.addAll(rows.map((r) => _Msg(
            fmt.s(r['role']),
            fmt.s(r['text']),
          )));
      _loaded = true;
    });
    _jumpToEnd();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    final services = AppScope.of(context);
    if (!services.sync.online) {
      toast(context, 'Chat needs the live agent - you are offline.',
          error: true);
      return;
    }
    HapticFeedback.selectionClick();
    _input.clear();
    setState(() {
      _busy = true;
      _messages.add(_Msg('user', text));
    });
    _jumpToEnd();
    await services.db.addChat('user', text);

    // Try to ACT before trying to talk: "mark the gap register done" should
    // do the thing, not describe how one might go about doing the thing.
    // Parsing is deterministic and instant, so this costs nothing when the
    // sentence turns out to only be a question (ported from the legacy
    // dashboard's tryAction()/sendRailChat(), dashboard/app.js:9399-9410).
    try {
      if (await _tryAction(text)) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    } catch (_) {
      // /api/act unreachable or errored -- fall through to normal chat
      // rather than surface a second error path for what the user just typed.
    }

    setState(() => _messages.add(_Msg('agent', '', pending: true)));
    _jumpToEnd();

    final reply = _messages.last;
    try {
      await for (final (event, data) in services.api.chatStream(text)) {
        if (!mounted) return;
        switch (event) {
          case 'status':
            setState(() => reply.via = fmt.s(data['via']));
          case 'token':
            setState(() {
              reply.pending = false;
              reply.text += fmt.s(data['t']);
            });
            _jumpToEnd();
          case 'done':
            setState(() {
              reply.pending = false;
              final full = fmt.s(data['response']);
              if (full.isNotEmpty) reply.text = full;
            });
            _jumpToEnd();
          case 'error':
            setState(() {
              reply.pending = false;
              if (reply.text.isEmpty) {
                reply.text = fmt.s(data['error']).isEmpty
                    ? 'The agent could not answer.'
                    : fmt.s(data['error']);
                reply.via = 'error';
              }
            });
        }
      }
      if (reply.text.isEmpty) {
        // Stream ended silently - fall back to the plain endpoint.
        final res = await services.api.postJson('/api/chat', {'message': text});
        reply.text = fmt.s(fmt.m(res)['response']);
        reply.pending = false;
        setState(() {});
      }
      await services.db.addChat('agent', reply.text);
    } on OfflineException {
      setState(() {
        reply.pending = false;
        reply.text = 'Connection dropped mid-answer.';
        reply.via = 'error';
      });
    } on ApiException catch (e) {
      setState(() {
        reply.pending = false;
        reply.text = e.authSuspect
            ? 'Session expired - please sign in again.'
            : e.message;
        reply.via = 'error';
      });
    } catch (e) {
      setState(() {
        reply.pending = false;
        reply.text = 'Unexpected error: $e';
        reply.via = 'error';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _jumpToEnd();
      }
    }
  }

  /// Attempts [text] as a deterministic action via hub's /act (spark's NLU).
  /// Returns true if /act understood it at all -- ambiguous, gated, or
  /// executed -- meaning the normal streaming chat turn should NOT also run.
  /// Ported from dashboard/app.js's tryAction() (~9524-9551).
  Future<bool> _tryAction(String text) async {
    final services = AppScope.of(context);
    final res =
        await services.api.postJson('/api/act', {'text': text});
    final d = fmt.m(res);
    if (!fmt.b(d['understood'])) return false;

    if (fmt.b(d['needsClarification'])) {
      final options = fmt.lm(d['options'])
          .map((o) => {'id': fmt.s(o['id']), 'title': fmt.s(o['title'])})
          .toList();
      setState(() {
        _messages.add(_Msg('agent', fmt.s(d['describe']))
          ..actionOptions = options);
      });
      _jumpToEnd();
      return true;
    }

    if (fmt.b(d['needsConfirmation'])) {
      setState(() {
        _messages.add(_Msg('agent', '')
          ..actionDescribe = fmt.s(d['describe'])
          ..actionPlan = fmt.m(d['plan']));
      });
      _jumpToEnd();
      return true;
    }

    await _applyActionResult(d);
    return true;
  }

  /// Renders the executed/failed result and nudges whichever Store
  /// snapshots the backend flagged as stale (dashboard/app.js's
  /// applyActionResult(), ~9585-9598). Navigation hints aren't wired yet --
  /// the result message already tells the user what happened.
  Future<void> _applyActionResult(Map<String, dynamic> d) async {
    final services = AppScope.of(context);
    final ok = d['ok'] == null ? true : fmt.b(d['ok']);
    final message = fmt.s(d['message']).isEmpty
        ? (ok ? 'Done.' : 'That did not work.')
        : fmt.s(d['message']);
    setState(() {
      final m = _Msg(ok ? 'agent' : 'error', message);
      if (!ok) m.via = 'error';
      _messages.add(m);
    });
    _jumpToEnd();
    await services.db.addChat('agent', message);

    for (final key in fmt.l(d['refresh']).map(fmt.s)) {
      switch (key) {
        case 'tasks':
          services.store.state.refresh();
        case 'jira':
          services.store.jira.refresh();
        case 'ideas':
          services.store.ideas.refresh();
      }
    }
  }

  Future<void> _confirmAction(_Msg msg) async {
    if (msg.actionPlan == null) return;
    final plan = msg.actionPlan!;
    setState(() {
      msg.actionPlan = null;
      msg.actionDescribe = null;
      msg.text = '';
    });
    final services = AppScope.of(context);
    try {
      final res = await services.api
          .postJson('/api/act', {'plan': plan, 'confirm': true});
      await _applyActionResult(fmt.m(res));
    } catch (e) {
      setState(() => _messages.add(_Msg('error', 'Could not complete that.')
        ..via = 'error'));
      _jumpToEnd();
    }
  }

  void _declineAction(_Msg msg) {
    setState(() {
      msg.actionPlan = null;
      msg.actionDescribe = null;
      msg.text = 'Left alone.';
    });
  }

  /// A disambiguation chip resends the request with the picked task's ID
  /// spliced in, matching the legacy quickAsk()'s `mark <ID> done` shape
  /// (dashboard/app.js:9604-9608) -- deliberately kept, not "improved",
  /// since that is the real production behaviour being ported.
  void _pickClarifyOption(_Msg msg, String id) {
    setState(() => msg.actionOptions = null);
    _send('mark $id done');
  }

  /// The agent keeps named conversations server-side, and the model's context
  /// window follows whichever one is open. Switching therefore has to be a
  /// server call, not a local filter - opening a thread here is what makes the
  /// agent answer inside it.
  ///
  /// Online-only for the same reason: there is no honest way to "open" a thread
  /// offline when the thing being changed lives on the other end.
  Future<void> _openThreads() async {
    final services = AppScope.of(context);
    final threads = services.store.chatThreads;
    threads.refresh();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => ListenableBuilder(
          listenable: threads,
          builder: (ctx, _) {
            final map = fmt.m(threads.value);
            final rows = fmt.lm(map['threads']);
            final current = fmt.s(map['current']);
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Row(
                  children: [
                    Text('Conversations', style: T.title),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _newThread();
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('New'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (threads.loading && rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: MiniSpinner(size: 20)),
                  )
                else if (rows.isEmpty)
                  const EmptyState('No saved conversations',
                      'Ask something and this one gets a name.',
                      icon: Icons.forum_outlined)
                else
                  for (final t in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Panel(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        borderColor: fmt.s(t['ID']) == current
                            ? C.greenDim.withValues(alpha: 0.6)
                            : C.border,
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _switchTo(fmt.s(t['ID']));
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fmt.s(t['TITLE']).isEmpty
                                        ? fmt.s(t['ID'])
                                        : fmt.s(t['TITLE']),
                                    style: T.w500(
                                        T.body2.copyWith(color: C.text)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(fmt.ago(t['UPDATED_AT']),
                                      style: T.monoSmall),
                                ],
                              ),
                            ),
                            if (fmt.s(t['ID']) == current)
                              const Badge2('open',
                                  color: C.greenBg, textColor: C.greenBright),
                          ],
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _switchTo(String id) async {
    final services = AppScope.of(context);
    try {
      final res =
          await services.mutations.post('/api/chat/thread/open', {'id': id});
      final msgs = fmt.lm(fmt.m(res)['messages']);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs.map((m) => _Msg(
                fmt.s(m['role']) == 'assistant' ? 'agent' : fmt.s(m['role']),
                fmt.s(m['content']),
              )));
      });
      _jumpToEnd();
    } catch (e) {
      if (mounted) toast(context, 'Could not open that thread', error: true);
    }
  }

  Future<void> _newThread() async {
    final services = AppScope.of(context);
    try {
      await services.mutations.post('/api/chat/thread/new', {});
      if (!mounted) return;
      setState(_messages.clear);
      toast(context, 'Started a new conversation');
    } catch (e) {
      if (mounted) toast(context, 'Could not start a new one', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Column(
      children: [
        // header
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
          child: Row(
            children: [
              const StatusDot(C.green, glow: true),
              const SizedBox(width: 10),
              Text('iSconl Assistant', style: T.title),
              const SizedBox(width: 10),
              const Badge2('Guardian Active',
                  color: C.greenBg, textColor: C.greenBright),
              const Spacer(),
              IconButton(
                tooltip: 'Conversations',
                icon: const Icon(Icons.forum_outlined, size: 19, color: C.text3),
                onPressed: services.sync.online ? _openThreads : null,
              ),
              if (!widget.embedded)
                IconButton(
                  icon:
                      const Icon(Icons.close_rounded, size: 20, color: C.text3),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: !_loaded
              ? const Center(child: MiniSpinner(size: 20))
              : _messages.isEmpty
                  ? const EmptyState(
                      'Ask the agent anything',
                      'It answers from your vault - tasks, finance, circle, '
                          'career. Try a quick prompt below.',
                      icon: Icons.forum_rounded,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, idx) =>
                          _bubble(_messages[idx]),
                    ),
        ),
        // quick chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              for (final chip in _quickChips)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Pill(chip, onTap: () => _send(chip)),
                ),
            ],
          ),
        ),
        // input
        ListenableBuilder(
          listenable: services.sync,
          builder: (context, _) {
            final online = services.sync.online;
            return Container(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 8,
                bottom: 10 + MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: C.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: online && !_busy,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      style: T.body2.copyWith(color: C.text),
                      decoration: InputDecoration(
                        hintText: online
                            ? 'Ask the agent…'
                            : 'Offline - chat needs the live agent',
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      onPressed:
                          online && !_busy ? () => _send(_input.text) : null,
                      child: _busy
                          ? const MiniSpinner()
                          : const Icon(Icons.arrow_upward_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _bubble(_Msg msg) {
    final isUser = msg.role == 'user';
    final isError = msg.via == 'error' || msg.role == 'error';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? C.greenBg
                    : isError
                        ? C.redBg
                        : C.surface,
                border: Border.all(
                  color: isUser
                      ? C.greenDim.withValues(alpha: 0.5)
                      : isError
                          ? C.red.withValues(alpha: 0.4)
                          : C.border,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(Sz.rLg),
                  topRight: const Radius.circular(Sz.rLg),
                  bottomLeft: Radius.circular(isUser ? Sz.rLg : Sz.rSm),
                  bottomRight: Radius.circular(isUser ? Sz.rSm : Sz.rLg),
                ),
              ),
              child: msg.pending
                  ? const _Thinking()
                  : msg.actionPlan != null
                      ? _actionConfirmCard(msg)
                      : msg.actionOptions != null
                          ? _actionClarifyCard(msg)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isUser)
                                  Text(msg.text, style: T.body2)
                                else
                                  Markdown(msg.text),
                                if (!isUser &&
                                    msg.via.isNotEmpty &&
                                    !isError)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text('via ${msg.via}',
                                        style: T.monoSmall
                                            .copyWith(fontSize: 9)),
                                  ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }

  /// A gated action awaiting yes/no (dashboard/app.js's renderActionConfirm(),
  /// ~9553-9583) -- nothing destructive or outward-facing happens because a
  /// regex felt confident.
  Widget _actionConfirmCard(_Msg msg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fmt.s(msg.actionDescribe), style: T.body2),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => _confirmAction(msg),
              child: const Text('Do it'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _declineAction(msg),
              child: const Text('Leave it'),
            ),
          ],
        ),
      ],
    );
  }

  /// An ambiguous task match, disambiguated by picking a chip
  /// (dashboard/app.js's clarification chips, ~9536-9541).
  Widget _actionClarifyCard(_Msg msg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(msg.text, style: T.body2),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in msg.actionOptions!)
              Pill(
                fmt.truncate(o['title'] ?? '', 40),
                onTap: () => _pickClarifyOption(msg, o['id'] ?? ''),
              ),
          ],
        ),
      ],
    );
  }
}

/// Three-dot thinking shimmer (kept under 200ms per pulse-step feel).
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var idx = 0; idx < 3; idx++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Opacity(
                  opacity: _pulse(idx),
                  child: const StatusDot(C.green, size: 6),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Triangular pulse travelling across the three dots.
  double _pulse(int idx) {
    final phase = (_c.value * 3 - idx) % 3;
    final tri = phase < 0 || phase > 1 ? 0.0 : 1 - (phase - 0.5).abs() * 2;
    return 0.25 + 0.75 * tri.clamp(0.0, 1.0);
  }
}
