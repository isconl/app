import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';
import '../widgets/sub_tabs.dart';
import 'ideas.dart';
import 'journal.dart';

/// BI26092651 and BI26100207: Codex, "what you thought, and what you did about it".
/// Journal and Ideas merged into one place, as on the web console on 16 Sep 2026
/// (UI label canon row 5). Both keep their own views and routes; Codex is the
/// tabs over them, with a Scans tab for captured pages.
class CodexView extends StatelessWidget {
  const CodexView({super.key});

  static const tabs = ['Journals', 'Ideas', 'Scans'];

  @override
  Widget build(BuildContext context) {
    return SubTabs(
      keyPrefix: 'codex',
      labels: tabs,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Text('what you thought, and what you did about it', key: const ValueKey('codex-subtitle'), style: T.small.copyWith(color: C.text3)),
      ),
      children: const [JournalView(), IdeasView(), CodexScansView()],
    );
  }
}

/// Captured pages. Nothing serves them to the phone yet, so this says so rather
/// than calling a route that does not exist and showing an error on every visit.
class CodexScansView extends StatelessWidget {
  const CodexScansView({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      'No scans yet',
      'Pages you capture will list here once the capture step is on the server. '
          'Journals and ideas work now.',
      icon: Icons.document_scanner_outlined,
    );
  }
}

/// What "Make it a task" did, for the caller to tell the user.
enum PromoteOutcome { done, queued, failed }

class PromoteResult {
  const PromoteResult(this.outcome, {this.error, this.stageMoved = false});
  final PromoteOutcome outcome;
  final String? error;

  /// Whether the idea was also moved to the `acted` stage (only when the server offers that stage).
  final bool stageMoved;
}

/// Turns an idea into a task: creates the task through the tasks API (queued when
/// offline, like every write), then moves the idea to `acted` if the server's stage
/// list has it. The idea keeps its own record; nothing is deleted.
Future<PromoteResult> promoteIdeaToTask(AppServices services, Map<String, dynamic> idea, List<String> stages) async {
  final title = fmt.s(idea['TITLE']);
  final id = fmt.s(idea['ID']);
  if (title.isEmpty || id.isEmpty || id == 'QUEUED') {
    return const PromoteResult(PromoteOutcome.failed, error: 'This idea has not synced yet. Try again once it has.');
  }
  final made = await services.mutations.addTask(title: title, status: 'backlog', tag: 'idea');
  if (!made.ok) return PromoteResult(PromoteOutcome.failed, error: made.error);
  var moved = false;
  if (stages.contains('acted')) {
    final res = await services.mutations.updateIdea(id, {'stage': 'acted'});
    moved = res.ok;
  }
  return PromoteResult(made.queued ? PromoteOutcome.queued : PromoteOutcome.done, stageMoved: moved);
}
/// BI26092651: the Codex fields on a journal entry or an idea: who can see it, which practices it belongs to, and its
/// Codex id once it has one. The id is minted by the server the first time the entry leaves private and never changes,
/// so it is shown, never edited. [onSave] sends the change and says whether it was accepted (or queued); a refusal
/// puts the control back where it was.
const codexVisibilities = ['private', 'unlisted', 'public'];

String codexVisibilityOf(Object? v) {
  final s = fmt.s(v).trim().toLowerCase();
  return codexVisibilities.contains(s) ? s : 'private';
}

/// '-' is how an empty cell arrives; it reads as nothing.
String codexCell(Object? v) {
  final s = fmt.s(v).trim();
  return s == '-' ? '' : s;
}

class CodexControls extends StatefulWidget {
  const CodexControls({super.key, required this.row, required this.onSave});

  final Map<String, dynamic> row;
  final Future<bool> Function(Map<String, dynamic> fields) onSave;

  @override
  State<CodexControls> createState() => _CodexControlsState();
}

class _CodexControlsState extends State<CodexControls> {
  late String _visibility = codexVisibilityOf(widget.row['VISIBILITY']);
  late final TextEditingController _practices = TextEditingController(text: codexCell(widget.row['PRACTICES']));
  bool _busy = false;

  @override
  void dispose() {
    _practices.dispose();
    super.dispose();
  }

  Future<void> _setVisibility(String next) async {
    if (_busy || next == _visibility) return;
    final before = _visibility;
    setState(() {
      _visibility = next;
      _busy = true;
    });
    final ok = await widget.onSave({'visibility': next});
    if (!mounted) return;
    setState(() {
      if (!ok) _visibility = before;
      _busy = false;
    });
  }

  Future<void> _savePractices() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onSave({'practices': _practices.text.trim()});
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final codexId = codexCell(widget.row['CODEX_ID']);
    final queued = fmt.s(widget.row['ID']) == 'QUEUED';
    if (queued) {
      return Text('Visibility and practices can be set once this has synced.', style: T.small.copyWith(color: C.text3));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('VISIBILITY', style: T.label.copyWith(letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Wrap(
          key: const ValueKey('codex-visibility'),
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in codexVisibilities)
              Pill(v, selected: v == _visibility, onTap: () => _setVisibility(v)),
          ],
        ),
        const SizedBox(height: 12),
        Field(label: 'Practices', controller: _practices, hint: 'comma,separated'),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('codex-save-practices'),
            onPressed: _busy ? null : _savePractices,
            child: const Text('Save practices'),
          ),
        ),
        if (codexId.isNotEmpty) KvRow('Codex id', codexId, mono: true),
      ],
    );
  }
}
