import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/markdown.dart';
import '../shell.dart' show ShellAppBar;
import '../widgets/common.dart';

/// People, by ring or full flat roster. Cards show cadence state; detail
/// view has the DIA profile, interactions, reachout suggestion, and native
/// contact actions.
class CircleView extends StatelessWidget {
  const CircleView({super.key, this.ring});
  final String? ring;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.circle,
      builder: (context, data) {
        final allPeople = fmt.lm(fmt.m(data)['people']);
        final people = ring == null || ring!.isEmpty || ring!.toLowerCase() == 'all'
            ? allPeople
            : allPeople
                .where((p) =>
                    fmt.s(p['CIRCLE']).toLowerCase() == ring!.toLowerCase())
                .toList();
        if (people.isEmpty) {
          return EmptyState(
            ring == null ? 'No contacts yet' : 'No one in $ring yet',
            'People appear here as the vault learns your circle.',
            icon: Icons.group_rounded,
          );
        }
        // due first, then by name
        people.sort((a, b) {
          final da = fmt.i(a['dueIn'], 9999);
          final db = fmt.i(b['dueIn'], 9999);
          if (da != db) return da.compareTo(db);
          return fmt.s(a['NAME']).compareTo(fmt.s(b['NAME']));
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final person in people)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PersonTile(person: person),
              ),
          ],
        );
      },
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});
  final Map<String, dynamic> person;

  @override
  Widget build(BuildContext context) {
    final dueIn = person['dueIn'];
    final overdue = dueIn != null && fmt.i(dueIn, 999) <= 0;
    final name = fmt.s(person['NAME']);
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PersonScreen(person: person)),
      ),
      child: Row(
        children: [
          _avatar(name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: T.w500(T.body2)),
                const SizedBox(height: 2),
                Text(
                  [
                    fmt.s(person['ROLE']),
                    if (fmt.s(person['lastTouch']).isNotEmpty)
                      'touched ${fmt.ago(person['lastTouch'])}',
                  ].where((x) => x.isNotEmpty).join(' · '),
                  style: T.monoSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (dueIn != null)
            Badge2(
              overdue ? 'due now' : 'in ${fmt.i(dueIn)}d',
              color: overdue ? C.amberBg : C.surface,
              textColor: overdue ? C.amber : C.text3,
            ),
        ],
      ),
    );
  }

  Widget _avatar(String name) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: C.greenBg,
        shape: BoxShape.circle,
        border: Border.all(color: C.greenDim.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(initials,
          style: T.mono.copyWith(
              color: C.greenBright, fontWeight: FontWeight.w500)),
    );
  }
}

class PersonScreen extends StatefulWidget {
  const PersonScreen({super.key, required this.person});
  final Map<String, dynamic> person;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = fmt.s(widget.person['ID']);
      if (id.isEmpty || !fmt.b(widget.person['hasDia'])) return;
      final services = AppScope.of(context);
      final snap = services.store
          .detail('dia', id, '/api/circle/dia?id=$id');
      snap.hydrate().then((_) {
        if (mounted && snap.value == null && services.sync.online) {
          snap.refresh();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final id = fmt.s(person['ID']);
    final name = fmt.s(person['NAME']);
    final recent = fmt.lm(person['recent']);
    final reachout = fmt.m(person['reachout']);

    return Scaffold(
      appBar: ShellAppBar(title: name, showBrand: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, style: T.title)),
                      Badge2(fmt.s(person['CIRCLE']),
                          color: C.greenBg, textColor: C.greenBright),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (fmt.s(person['ROLE']).isNotEmpty)
                    KvRow('Role', fmt.s(person['ROLE'])),
                  if (fmt.s(person['GROUP']).isNotEmpty)
                    KvRow('Group', fmt.s(person['GROUP'])),
                  if (fmt.s(person['CHANNEL']).isNotEmpty)
                    KvRow('Channel', fmt.s(person['CHANNEL'])),
                  if (fmt.s(person['CADENCE']).isNotEmpty)
                    KvRow('Cadence', fmt.s(person['CADENCE'])),
                  KvRow('Last touch',
                      fmt.s(person['lastTouch']).isEmpty
                          ? 'never'
                          : fmt.ago(person['lastTouch'])),
                  const SizedBox(height: 10),
                  // Native actions: dial / message apps via the channel field.
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openChannel(person),
                        icon: const Icon(Icons.send_rounded, size: 15),
                        label: const Text('Reach out'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _touchSheet(context, id),
                        icon: const Icon(Icons.handshake_rounded, size: 15),
                        label: const Text('Log touch'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (reachout.isNotEmpty &&
                fmt.s(reachout['why']).isNotEmpty) ...[
              const SectionLabel('Why reach out now'),
              Panel(
                color: C.greenBg2,
                borderColor: C.greenDim.withValues(alpha: 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmt.s(reachout['why']), style: T.body2),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (fmt.s(reachout['urgency']).isNotEmpty)
                          Badge2(fmt.s(reachout['urgency']),
                              color: C.amberBg, textColor: C.amber),
                        if (fmt.s(reachout['channel']).isNotEmpty)
                          Badge2(fmt.s(reachout['channel'])),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (recent.isNotEmpty) ...[
              const SectionLabel('Recent interactions'),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var idx = 0; idx < recent.length && idx < 8; idx++) ...[
                      if (idx > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sz.pad, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(fmt.shortDate(recent[idx]['DATE']),
                                    style: T.monoSmall
                                        .copyWith(color: C.greenBright)),
                                const SizedBox(width: 8),
                                if (fmt
                                    .s(recent[idx]['CHANNEL'])
                                    .isNotEmpty)
                                  Badge2(fmt.s(recent[idx]['CHANNEL'])),
                              ],
                            ),
                            if (fmt.s(recent[idx]['SUMMARY']).isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(fmt.s(recent[idx]['SUMMARY']),
                                  style: T.small.copyWith(color: C.text2)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (fmt.b(person['hasDia'])) ...[
              const SectionLabel('DIA profile'),
              _DiaCard(personId: id),
            ],
          ],
        ),
      ),
    );
  }

  /// Open the person's preferred channel natively.
  Future<void> _openChannel(Map<String, dynamic> person) async {
    final channel = fmt.s(person['CHANNEL']).toLowerCase();
    final note = fmt.s(person['NOTE']);
    // Phone numbers sometimes live in the note/channel columns.
    final phoneMatch =
        RegExp(r'(\+?\d[\d\s-]{7,})').firstMatch('$channel $note');
    Uri? uri;
    if (channel.contains('whatsapp') && phoneMatch != null) {
      uri = Uri.parse(
          'https://wa.me/${phoneMatch.group(1)!.replaceAll(RegExp(r'[^\d]'), '')}');
    } else if (channel.contains('mail')) {
      final mail = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').firstMatch(note);
      if (mail != null) uri = Uri.parse('mailto:${mail.group(0)}');
    } else if (phoneMatch != null) {
      uri = Uri.parse(
          'tel:${phoneMatch.group(1)!.replaceAll(RegExp(r'[^\d+]'), '')}');
    }
    if (uri == null) {
      if (mounted) {
        toast(context,
            'No contact handle on file - log a touch instead.');
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _touchSheet(BuildContext context, String id) {
    final summary = TextEditingController();
    final next = TextEditingController();
    var channel = 'whatsapp';
    final services = AppScope.of(context);
    return showFormSheet(
      context,
      title: 'Log touch',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Segmented(
              label: 'Channel',
              options: const ['whatsapp', 'call', 'in-person', 'email'],
              value: channel,
              onChanged: (v) => setSheet(() => channel = v),
            ),
            Field(
                label: 'What happened?',
                controller: summary,
                maxLines: 3,
                autofocus: true),
            Field(label: 'Next step (optional)', controller: next),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await services.mutations.logTouch(
                  personId: id,
                  channel: channel,
                  summary: summary.text.trim(),
                  next: next.text.trim(),
                );
                if (!context.mounted) return;
                if (!res.ok) {
                  toast(context, res.error!, error: true);
                } else if (res.queued) {
                  toast(context, 'Touch logged - queued for sync');
                }
              },
              child: const Text('Log'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiaCard extends StatelessWidget {
  const _DiaCard({required this.personId});
  final String personId;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final snap = services.store
        .detail('dia', personId, '/api/circle/dia?id=$personId');
    return ListenableBuilder(
      listenable: snap,
      builder: (context, _) {
        final content = fmt.s(fmt.m(snap.value)['content']);
        if (content.isEmpty) {
          return Panel(
            child: Row(
              children: [
                if (snap.loading) const MiniSpinner(),
                if (snap.loading) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    snap.loading
                        ? 'Loading profile…'
                        : 'Profile loads when online, then stays cached '
                            'for offline reading.',
                    style: T.small,
                  ),
                ),
                if (!snap.loading)
                  TextButton(
                      onPressed: () => snap.refresh(),
                      child: const Text('Load')),
              ],
            ),
          );
        }
        return Panel(child: Markdown(content));
      },
    );
  }
}

/// Flat contacts roster (all circles, no filter).
class ContactsView extends StatelessWidget {
  const ContactsView({super.key});

  @override
  Widget build(BuildContext context) => const CircleView();
}

