import 'dart:async';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../views/task_detail.dart';
import 'common.dart';

/// One palette for the day blocks, ported from web's BLOCK_TONE (app.js ~9856).
const Map<String, Color> kBlockTones = {
  'protected': Color(0xFF8B9EEC),
  'learning': Color(0xFF3FB6D3),
  'study': Color(0xFF3FB6D3),
  'flex': Color(0xFF7C828D),
  'innovator': Color(0xFF22B573),
  'visionary': Color(0xFF4A7FE8),
  'leadership': Color(0xFF4A7FE8),
  'lunch': Color(0xFFD9A441),
  'creator': Color(0xFFF2792A),
  'creative': Color(0xFFF2792A),
  'connection': Color(0xFFEA5A9E),
  'home': Color(0xFF4A9C86),
  'rest': Color(0xFF43458F),
};

/// How far through a block `now` is, 0.0 to 1.0, from its `HH:MM` start and end clocks. Null when either
/// clock is missing or unreadable, or `now` is outside the block (so no bar is drawn for it).
double? blockProgress(String startClock, String endClock, DateTime now) {
  int? mins(String c) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(c.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
    return h > 23 || mi > 59 ? null : h * 60 + mi;
  }

  final s = mins(startClock), e = mins(endClock);
  if (s == null || e == null || e <= s) return null;
  final n = now.hour * 60 + now.minute;
  if (n < s || n >= e) return null;
  return (n - s) / (e - s);
}

Color blockToneOf(Map<String, dynamic>? block) {
  if (block == null) return C.text3;
  final toneStr = fmt.s(block['tone'] ?? block['color'] ?? block['axis'] ?? block['id']);
  return kBlockTones[toneStr.toLowerCase()] ?? C.green;
}

/// The Hub block card (BI26092625 + BI26092628).
///
/// Displays the current or next block with up to 3 placed items.
/// Supports swipe actions (right = Done, left = Move to next) and
/// long-press opening a sheet with Pin, Move, Defer, Start, Done.
class BlockCard extends StatefulWidget {
  const BlockCard({
    super.key,
    required this.blocks,
    this.currentId,
    this.onViewTasks,
  });

  final List<Map<String, dynamic>> blocks;
  final String? currentId;
  final VoidCallback? onViewTasks;

  @override
  State<BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends State<BlockCard> {
  bool _showNext = false;
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    // The progress bar on the now block moves once a minute.
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  int get _currentIndex {
    if (widget.blocks.isEmpty) return 0;
    final idx = widget.blocks.indexWhere((b) =>
        fmt.s(b['id']).toLowerCase() == widget.currentId?.toLowerCase());
    return idx >= 0 ? idx : 0;
  }

  int get _nextIndex {
    if (widget.blocks.isEmpty) return 0;
    return (_currentIndex + 1) % widget.blocks.length;
  }

  Map<String, dynamic>? get _activeBlock {
    if (widget.blocks.isEmpty) return null;
    final idx = _showNext ? _nextIndex : _currentIndex;
    return widget.blocks[idx];
  }

  @override
  Widget build(BuildContext context) {
    final block = _activeBlock;
    if (block == null) {
      return const Panel(
        child: Text('Reading your blocks…', style: TextStyle(color: C.text3)),
      );
    }

    final blockId = fmt.s(block['id']);
    final blockName = fmt.s(block['name']).isEmpty ? 'Day' : fmt.s(block['name']);
    final tone = blockToneOf(block);
    final placeable = block['placeable'] != false;
    final rawTasks = fmt.l(block['tasks']);
    final tasks = rawTasks.map((t) => Map<String, dynamic>.from(fmt.m(t))).toList();
    final slots = fmt.i(block['slots']);
    final note = fmt.s(block['note']);
    final isNow = !_showNext;

    final startClock = fmt.s(block['startClock']);
    final endClock = fmt.s(block['endClock']);
    final timeRange = startClock.isNotEmpty && endClock.isNotEmpty
        ? '$startClock - $endClock'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Header row with NOW / NEXT toggle ----
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tone,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isNow ? 'NOW · $blockName' : 'NEXT · $blockName',
                  style: T.label.copyWith(color: tone, letterSpacing: 1.0),
                ),
                if (timeRange.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    timeRange,
                    style: T.tiny.copyWith(color: C.text3),
                  ),
                ],
                if (block['quiet'] == true) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: C.surface,
                      borderRadius: BorderRadius.circular(Sz.rSm),
                      border: Border.all(color: C.border),
                    ),
                    child: Text('quiet', style: T.tiny.copyWith(color: C.text3, fontSize: 10)),
                  ),
                ],
              ],
            ),
            if (widget.blocks.length > 1)
              TextButton(
                onPressed: () => setState(() => _showNext = !_showNext),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(isNow ? 'Next' : 'Now'),
              ),
          ],
        ),
        const SizedBox(height: 6),

        // ---- Block Card Body ----
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Capacity & block meta
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    placeable
                        ? (slots > 0 ? '${tasks.length}/$slots placed' : '${tasks.length} tasks')
                        : 'Personal time',
                    style: T.tiny.copyWith(color: C.text3),
                  ),
                  if (note.isNotEmpty && placeable)
                    Expanded(
                      child: Text(
                        note,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: T.tiny.copyWith(color: C.text3),
                      ),
                    ),
                ],
              ),
              // The now block's progress through its time range (BI26092625).
              if (isNow && blockProgress(startClock, endClock, DateTime.now()) != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    key: const Key('block-progress'),
                    value: blockProgress(startClock, endClock, DateTime.now()),
                    minHeight: 3,
                    backgroundColor: C.border,
                    valueColor: AlwaysStoppedAnimation(tone),
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // Non-placeable block: show note
              if (!placeable)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    note.isNotEmpty ? note : 'Personal time',
                    style: T.body2.copyWith(color: C.text3),
                  ),
                )
              // Placeable block with no items
              else if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Nothing placed here yet.',
                    style: TextStyle(color: C.text3),
                  ),
                )
              // Placeable block with items (up to 3)
              else ...[
                for (var i = 0; i < tasks.length && i < 3; i++)
                  _BlockItemTile(
                    key: ValueKey('block_task_${fmt.s(tasks[i]['id'] ?? tasks[i]['ID'])}'),
                    task: tasks[i],
                    blockId: blockId,
                  ),
                if (tasks.length > 3)
                  InkWell(
                    borderRadius: BorderRadius.circular(Sz.rSm),
                    onTap: widget.onViewTasks,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Center(
                        child: Text(
                          '+${tasks.length - 3} more',
                          style: T.tiny.copyWith(
                            color: C.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One task item inside a block card.
///
/// Supports:
/// - Swipe right = Done
/// - Swipe left = Move to next
/// - Long-press = 5-action bottom sheet (Pin here, Move to next, Not today, Start, Done)
/// - Tap = Open task detail screen
class _BlockItemTile extends StatefulWidget {
  const _BlockItemTile({
    super.key,
    required this.task,
    required this.blockId,
  });

  final Map<String, dynamic> task;
  final String blockId;

  @override
  State<_BlockItemTile> createState() => _BlockItemTileState();
}

class _BlockItemTileState extends State<_BlockItemTile> {
  Timer? _ticker;

  String get _taskId => fmt.s(widget.task['id'] ?? widget.task['ID']);
  String get _title => fmt.s(widget.task['title'] ?? widget.task['TITLE']);
  bool get _isPinned => widget.task['pinned'] == true || widget.task['PINNED'] == true;
  bool get _isStarted => widget.task['started'] == true || widget.task['STARTED'] == true;

  @override
  void initState() {
    super.initState();
    if (_isStarted) {
      _startTicker();
    }
  }

  @override
  void didUpdateWidget(covariant _BlockItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isStarted && _ticker == null) {
      _startTicker();
    } else if (!_isStarted && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed() {
    final rawStarted = widget.task['startedAt'] ?? widget.task['STARTED_AT'];
    DateTime? startedAt;
    if (rawStarted is String) {
      startedAt = DateTime.tryParse(rawStarted);
    } else if (rawStarted is int) {
      startedAt = DateTime.fromMillisecondsSinceEpoch(rawStarted);
    }
    startedAt ??= DateTime.now();
    final elapsedSec = DateTime.now().difference(startedAt).inSeconds.clamp(0, 86400);
    final m = (elapsedSec ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _openActionSheet(BuildContext context) {
    final services = AppScope.of(context);
    final why = fmt.s(widget.task['why'] ?? widget.task['WHY']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
        side: BorderSide(color: C.border),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: C.borderMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title, style: T.headline, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (why.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Placed here because it $why',
                          style: T.tiny.copyWith(color: C.text3)),
                    ],
                  ],
                ),
              ),
              const Divider(color: C.border),
              ListTile(
                leading: Icon(
                  _isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  color: _isPinned ? C.text3 : C.green,
                ),
                title: Text(_isPinned ? 'Unpin' : 'Pin here'),
                onTap: () {
                  Navigator.pop(ctx);
                  services.mutations.dayPin(_taskId, blockId: widget.blockId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_forward_rounded, color: C.cyan),
                title: const Text('Move to next'),
                onTap: () {
                  Navigator.pop(ctx);
                  services.mutations.dayMove(_taskId, blockId: widget.blockId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_busy_rounded, color: C.amber),
                title: const Text('Not today'),
                onTap: () {
                  Navigator.pop(ctx);
                  services.mutations.dayDefer(_taskId, blockId: widget.blockId);
                },
              ),
              ListTile(
                leading: Icon(
                  _isStarted ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded,
                  color: _isStarted ? C.red : C.green,
                ),
                title: Text(_isStarted ? 'Stop' : 'Start'),
                onTap: () {
                  Navigator.pop(ctx);
                  services.mutations.dayStart(_taskId, blockId: widget.blockId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_rounded, color: C.green),
                title: const Text('Done'),
                onTap: () {
                  Navigator.pop(ctx);
                  services.mutations.dayDone(_taskId, blockId: widget.blockId);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final dueDate = fmt.s(widget.task['due'] ?? widget.task['DUE_DATE']);
    final isOverdue = widget.task['overdue'] == true ||
        (dueDate.isNotEmpty && (fmt.daysUntil(dueDate) ?? 0) < 0);
    final dueToday = widget.task['dueToday'] == true ||
        (dueDate.isNotEmpty && fmt.daysUntil(dueDate) == 0);
    final priority = fmt.s(widget.task['priority'] ?? widget.task['PRIORITY']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('dismiss_block_task_$_taskId'),
        direction: DismissDirection.horizontal,
        background: Container(
          decoration: BoxDecoration(
            color: C.green,
            borderRadius: BorderRadius.circular(Sz.rMd),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: C.textInverse, size: 20),
              SizedBox(width: 8),
              Text(
                'Done',
                style: TextStyle(color: C.textInverse, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        secondaryBackground: Container(
          decoration: BoxDecoration(
            color: C.cyan,
            borderRadius: BorderRadius.circular(Sz.rMd),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Move to next',
                style: TextStyle(color: C.textInverse, fontWeight: FontWeight.w600),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: C.textInverse, size: 20),
            ],
          ),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // Swipe right = Done
            await services.mutations.dayDone(_taskId, blockId: widget.blockId);
            return true;
          } else if (direction == DismissDirection.endToStart) {
            // Swipe left = Move to next
            await services.mutations.dayMove(_taskId, blockId: widget.blockId);
            return true;
          }
          return false;
        },
        child: Container(
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(Sz.rMd),
            border: Border.all(color: C.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Sz.rMd),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskDetailScreen(taskId: _taskId),
                ),
              );
            },
            onLongPress: () => _openActionSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: T.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (_isPinned) ...[
                              const Icon(Icons.push_pin_rounded,
                                  size: 13, color: C.green),
                              const SizedBox(width: 4),
                            ],
                            if (_isStarted) ...[
                              Text(
                                _formatElapsed(),
                                style: T.mono.copyWith(
                                  color: C.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('·', style: T.tiny.copyWith(color: C.text3)),
                              const SizedBox(width: 6),
                            ],
                            if (isOverdue)
                              Text(
                                'overdue ${fmt.dueLabel(dueDate)}',
                                style: T.tiny.copyWith(
                                  color: C.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else if (dueToday)
                              Text(
                                'due today',
                                style: T.tiny.copyWith(color: C.green),
                              )
                            else if (priority.isNotEmpty)
                              Text(
                                priority,
                                style: T.tiny.copyWith(
                                  color: C.forPriority(priority),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
