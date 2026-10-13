import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/mutations.dart' show MutationResult;
import '../../theme.dart';
import '../../util/circle_tags.dart';
import '../../util/fmt.dart' as fmt;
import '../shell.dart' show ShellAppBar;
import '../widgets/common.dart';

/// BI26100507: Circle tag management, as the console has it. Every tag in use with its count; rename, merge
/// and delete each say how many people they change and ask before doing it. Those three rewrite every
/// contact carrying the tag, so they need the live server; adding or removing a tag on one person (the
/// person page) also works offline.
class CircleTagsScreen extends StatelessWidget {
  const CircleTagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: const ShellAppBar(title: 'Tags', showBrand: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
        child: SnapshotView(
          snapshot: services.store.circle,
          builder: (context, data) {
            final people = fmt.lm(fmt.m(data)['people']);
            final tags = tagCounts(people);
            if (tags.isEmpty) {
              return const EmptyState('No tags yet', 'Add a tag from a person\'s page and it appears here.',
                  icon: Icons.sell_rounded);
            }
            return Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < tags.length; i++) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      key: ValueKey('tag-${tags[i].tag}'),
                      title: Text(tags[i].tag, style: T.body2),
                      subtitle: Text('${tags[i].count} ${tags[i].count == 1 ? 'person' : 'people'}', style: T.monoSmall),
                      trailing: PopupMenuButton<String>(
                        key: ValueKey('tag-menu-${tags[i].tag}'),
                        tooltip: 'Tag actions',
                        onSelected: (a) => switch (a) {
                          'rename' => _rename(context, people, tags[i].tag),
                          'merge' => _merge(context, people, tags, tags[i].tag),
                          _ => _delete(context, people, tags[i].tag),
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'merge', child: Text('Merge into another tag')),
                          PopupMenuItem(value: 'delete', child: Text('Delete from everyone')),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, List<Map<String, dynamic>> people, String from) async {
    final to = await _askName(context, 'Rename "$from"', from);
    if (to == null || to == from || !context.mounted) return;
    final n = peopleWithAnyTag(people, [from]);
    final sure = await confirmDialog(context, 'Rename to "$to"?', 'This changes the tag on ${_people(n)}.',
        action: 'Rename');
    if (!sure || !context.mounted) return;
    _report(context, await AppScope.of(context).mutations.renameTag(from, to), 'Renamed on ${_people(n)}');
  }

  Future<void> _merge(BuildContext context, List<Map<String, dynamic>> people,
      List<({String tag, int count})> tags, String source) async {
    final into = await showFormSheet<String>(
      context,
      title: 'Merge "$source" into',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in tags.where((t) => t.tag != source))
            ListTile(
              key: ValueKey('merge-into-${t.tag}'),
              title: Text(t.tag),
              subtitle: Text(_people(t.count)),
              onTap: () => Navigator.pop(ctx, t.tag),
            ),
        ],
      ),
    );
    if (into == null || !context.mounted) return;
    final n = peopleWithAnyTag(people, [source]);
    final sure = await confirmDialog(context, 'Merge "$source" into "$into"?',
        '${_people(n, capital: true)} carrying "$source" will carry "$into" instead, and "$source" goes away.',
        action: 'Merge');
    if (!sure || !context.mounted) return;
    _report(context, await AppScope.of(context).mutations.mergeTags([source], into), 'Merged on ${_people(n)}');
  }

  Future<void> _delete(BuildContext context, List<Map<String, dynamic>> people, String tag) async {
    final n = peopleWithAnyTag(people, [tag]);
    final sure = await confirmDialog(context, 'Delete "$tag"?',
        'It comes off ${_people(n)}. The people stay; only the tag goes.', action: 'Delete', destructive: true);
    if (!sure || !context.mounted) return;
    _report(context, await AppScope.of(context).mutations.deleteTag(tag), 'Deleted from ${_people(n)}');
  }

  static String _people(int n, {bool capital = false}) {
    final s = n == 1 ? '1 person' : '$n people';
    return capital ? s[0].toUpperCase() + s.substring(1) : s;
  }
}

/// The tag chips on a person's page: tap the cross to remove one, Add tag for a new one.
class PersonTagsPanel extends StatelessWidget {
  const PersonTagsPanel({super.key, required this.personId});
  final String personId;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.store.circle,
      builder: (context, _) {
        final person = fmt.lm(fmt.m(services.store.circle.value)['people'])
            .firstWhere((p) => fmt.s(p['ID']) == personId, orElse: () => const {});
        final tags = parseTags(person['TAGS']);
        return Panel(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in tags)
                InputChip(
                  key: ValueKey('person-tag-$t'),
                  label: Text(t),
                  onDeleted: () async =>
                      _report(context, await services.mutations.removePersonTag(personId, t), 'Removed "$t"'),
                ),
              ActionChip(
                key: const Key('person-tag-add'),
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add tag'),
                onPressed: () async {
                  final tag = await _askName(context, 'Add a tag', '');
                  if (tag == null || tags.contains(tag) || !context.mounted) return;
                  _report(context, await services.mutations.addPersonTag(personId, tag), 'Tagged "$tag"');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<String?> _askName(BuildContext context, String title, String initial) async {
  final ctl = TextEditingController(text: initial);
  final raw = await showFormSheet<String>(
    context,
    title: title,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Field(label: 'Tag', controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
      ],
    ),
  );
  if (raw == null) return null;
  final tag = cleanTag(raw);
  return tag.isEmpty ? null : tag;
}

void _report(BuildContext context, MutationResult res, String done) {
  if (!context.mounted) return;
  if (!res.ok) {
    toast(context, res.error!, error: true);
  } else {
    toast(context, res.queued ? '$done, queued for sync' : done);
  }
}
