import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// The axial tree: AX-WRI / AX-VIS / AX-INN / AX-CRE.
class SpacesView extends StatelessWidget {
  const SpacesView({super.key, this.axis});
  final String? axis;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.spaces,
      builder: (context, data) {
        final allTree = fmt.lm(fmt.m(data)['tree']);
        final tree = axis == null || axis!.isEmpty
            ? allTree
            : allTree.where((n) {
                final id = fmt.s(n['ID']).toUpperCase();
                final name = fmt.s(n['NAME'] ?? n['TITLE']).toUpperCase();
                final target = axis!.toUpperCase();
                return id.contains(target) || name.contains(target);
              }).toList();
        if (tree.isEmpty) {
          return EmptyState(
            axis == null ? 'No spaces yet' : 'No $axis space yet',
            'The trifractal tree appears after the first sync.',
            icon: Icons.hub_rounded,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final node in tree)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SpaceNode(node: node, depth: 0),
              ),
          ],
        );
      },
    );
  }
}

class _SpaceNode extends StatefulWidget {
  const _SpaceNode({required this.node, required this.depth});
  final Map<String, dynamic> node;
  final int depth;

  @override
  State<_SpaceNode> createState() => _SpaceNodeState();
}

class _SpaceNodeState extends State<_SpaceNode> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final children = fmt.lm(node['children']);
    final title =
        fmt.s(node['TITLE']).isEmpty ? fmt.s(node['NAME']) : fmt.s(node['TITLE']);
    final id = fmt.s(node['ID']);
    final count = fmt.i(node['descendantCount']);

    final header = InkWell(
      onTap: children.isEmpty ? null : () => setState(() => _open = !_open),
      child: Padding(
        padding: EdgeInsets.only(
            left: 4.0 + widget.depth * 16, top: 8, bottom: 8, right: 4),
        child: Row(
          children: [
            Icon(
              children.isEmpty
                  ? Icons.circle_outlined
                  : _open
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
              size: children.isEmpty ? 8 : 16,
              color: C.text3,
            ),
            const SizedBox(width: 8),
            if (id.isNotEmpty) ...[
              Text(id,
                  style: T.monoSmall.copyWith(
                      color: id.startsWith('AX') ? C.greenBright : C.text3)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(title,
                  style: widget.depth == 0 ? T.w600(T.body2) : T.small),
            ),
            if (count > 0) Badge2('$count'),
          ],
        ),
      ),
    );

    if (widget.depth == 0) {
      return Panel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (_open)
              for (final child in children)
                _SpaceNode(node: child, depth: widget.depth + 1),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (_open)
          for (final child in children)
            _SpaceNode(node: child, depth: widget.depth + 1),
      ],
    );
  }
}
