import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// BG26091303: drive-wide Backlog, mirroring the web console's own
/// Backlog space (BI26091301) -- same /api/backlog endpoint, grouped by
/// project then category, with a search box and category/project filter
/// chips. `TasksView`'s Pill-based filter-row convention reused rather
/// than inventing a new one.
class BacklogView extends StatefulWidget {
  const BacklogView({super.key});

  @override
  State<BacklogView> createState() => _BacklogViewState();
}

const _categoryLabels = {
  'plan': 'Plan', 'build': 'Build', 'work': 'Work', 'light': 'Light',
  'content': 'Content', 'hands': 'Hands', 'shelved': 'Shelved',
};

class _BacklogViewState extends State<BacklogView> {
  String _query = '';
  String _category = 'all';
  String _project = 'all';

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.backlog,
      builder: (context, data) {
        final all = fmt.lm(fmt.m(data)['projects']);
        if (all.isEmpty) {
          return const EmptyState(
            'No live rows',
            'Every project backlog is empty right now, or the drive-wide '
                'view could not be reached.',
            icon: Icons.checklist_rounded,
          );
        }

        final projectNames = all.map((p) => fmt.s(p['project'])).toList()
          ..sort();
        final categories = <String>{};
        for (final p in all) {
          for (final r in fmt.lm(p['rows'])) {
            categories.add(fmt.s(r['category']));
          }
        }
        final sortedCategories = categories.toList()
          ..sort((a, b) => _categoryLabels.keys
              .toList()
              .indexOf(a)
              .compareTo(_categoryLabels.keys.toList().indexOf(b)));

        final q = _query.trim().toLowerCase();
        bool matches(Map<String, dynamic> row, String project) {
          if (_category != 'all' && fmt.s(row['category']) != _category) {
            return false;
          }
          if (_project != 'all' && project != _project) return false;
          if (q.isNotEmpty) {
            final hay =
                '${fmt.s(row['id'])} ${fmt.s(row['title'])}'.toLowerCase();
            if (!hay.contains(q)) return false;
          }
          return true;
        }

        final visible = <Map<String, dynamic>>[];
        var totalRows = 0;
        for (final p in all) {
          final project = fmt.s(p['project']);
          final rows = fmt.lm(p['rows'])
              .where((r) => matches(r, project))
              .toList();
          final docs = fmt.lm(p['documents']);
          final showDocs = _category == 'all' &&
              q.isEmpty &&
              (_project == 'all' || _project == project);
          if (rows.isEmpty && !(showDocs && docs.isNotEmpty)) continue;
          totalRows += rows.length;
          visible.add({'project': project, 'rows': rows, 'documents': showDocs ? docs : []});
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search ID or title…',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Pill('all',
                      selected: _category == 'all',
                      onTap: () => setState(() => _category = 'all')),
                  const SizedBox(width: 6),
                  for (final c in sortedCategories) ...[
                    Pill(_categoryLabels[c] ?? c,
                        selected: _category == c,
                        onTap: () => setState(() => _category = c)),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Pill('all projects',
                      selected: _project == 'all',
                      onTap: () => setState(() => _project = 'all')),
                  const SizedBox(width: 6),
                  for (final p in projectNames) ...[
                    Pill(p,
                        selected: _project == p,
                        onTap: () => setState(() => _project = p)),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('$totalRows row${totalRows == 1 ? '' : 's'} across ${visible.length} project${visible.length == 1 ? '' : 's'}',
                  style: T.small.copyWith(color: C.text3)),
            ),
            if (visible.isEmpty)
              const EmptyState('No matches', 'Nothing matches this filter.',
                  icon: Icons.search_off_rounded)
            else
              for (final p in visible) _ProjectSection(p),
          ],
        );
      },
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection(this.data);
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rows = fmt.lm(data['rows']);
    final docs = fmt.lm(data['documents']);
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      byCategory.putIfAbsent(fmt.s(r['category']), () => []).add(r);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fmt.s(data['project']),
                style: T.w600(T.body.copyWith(color: C.text))),
            for (final entry in byCategory.entries) ...[
              const SizedBox(height: 8),
              Text(_categoryLabels[entry.key] ?? entry.key,
                  style: T.small.copyWith(color: C.text3)),
              for (final r in entry.value) _BacklogRow(r),
            ],
            if (docs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Documents', style: T.small.copyWith(color: C.text3)),
              for (final d in docs) _DocumentRow(d),
            ],
          ],
        ),
      ),
    );
  }
}

class _BacklogRow extends StatelessWidget {
  const _BacklogRow(this.row);
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final legacy = fmt.s(row['legacySource']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fmt.s(row['id']), style: T.monoSmall),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: fmt.s(row['title']), style: T.small),
                if (legacy.isNotEmpty)
                  TextSpan(
                      text: ' (legacy $legacy, pre-migration)',
                      style: T.small.copyWith(color: C.text3)),
              ]),
            ),
          ),
          if (fmt.s(row['status']).isNotEmpty)
            Text(fmt.s(row['status']), style: T.small.copyWith(color: C.text3)),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow(this.doc);
  final Map<String, dynamic> doc;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(fmt.s(doc['url']));
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(fmt.s(doc['name']),
                  style: T.small.copyWith(
                      color: C.text2, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }
}
