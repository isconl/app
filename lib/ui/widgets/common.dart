import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/store.dart';
import '../../theme.dart';

/// 1px-bordered panel card - the dashboard's base surface.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Sz.pad),
    this.onTap,
    this.onLongPress,
    this.color = C.panel,
    this.borderColor = C.border,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(Sz.rMd),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onTap!();
                      },
                onLongPress: onLongPress,
                child: body,
              ),
            ),
    );
  }
}

/// Uppercase micro-label used for section headers (nav-group style).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding});
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: T.label),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// Small mono badge (counts, IDs, statuses).
class Badge2 extends StatelessWidget {
  const Badge2(this.text,
      {super.key,
      this.color = C.surface,
      this.textColor = C.text2,
      this.borderColor});
  final String text;
  final Color color;
  final Color textColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Text(text,
          style: T.monoSmall.copyWith(
              color: textColor, fontWeight: FontWeight.w500, fontSize: 10.5)),
    );
  }
}

/// 6px status dot; glows when [glow].
class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.glow = false, this.size = 7});
  final Color color;
  final bool glow;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [BoxShadow(color: C.greenGlow, blurRadius: 6, spreadRadius: 1)]
            : null,
      ),
    );
  }
}

/// Selectable pill chip row item.
class Pill extends StatelessWidget {
  const Pill(this.label,
      {super.key, this.selected = false, this.onTap, this.color});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? C.green;
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? C.greenBg : C.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : C.border),
        ),
        child: Text(
          label,
          style: T.small.copyWith(
            color: selected ? C.greenBright : C.text2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Empty states teach (constitution 5.2).
class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.hint, {super.key, this.icon});
  final String title;
  final String hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.check_circle_outline_rounded,
                size: 34, color: C.text3.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(title,
                style: T.w600(T.body2.copyWith(color: C.text2)),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(hint,
                style: T.small.copyWith(color: C.text3),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// 14px dashboard spinner: border ring with a green top arc.
class MiniSpinner extends StatefulWidget {
  const MiniSpinner({super.key, this.size = 14});
  final double size;

  @override
  State<MiniSpinner> createState() => _MiniSpinnerState();
}

class _MiniSpinnerState extends State<MiniSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: C.green,
          backgroundColor: C.border,
        ),
      ),
    );
  }
}

/// Inline error row with retry.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = message == 'offline';
    return Panel(
      color: offline ? C.panel : C.redBg,
      borderColor: offline ? C.border : C.red.withValues(alpha: 0.4),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(offline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
              size: 16, color: offline ? C.text3 : C.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              offline
                  ? 'Offline - showing the last synced copy.'
                  : message,
              style: T.small.copyWith(color: offline ? C.text3 : C.text2),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Key-value row used inside cards.
class KvRow extends StatelessWidget {
  const KvRow(this.k, this.v, {super.key, this.vColor, this.mono = false});
  final String k;
  final String v;
  final Color? vColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(k, style: T.small.copyWith(color: C.text3))),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : v,
              style: mono
                  ? T.mono.copyWith(color: vColor ?? C.text2)
                  : T.small.copyWith(color: vColor ?? C.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard scrollable view body: cache-first snapshot with pull-to-refresh.
class SnapshotView extends StatefulWidget {
  const SnapshotView({
    super.key,
    required this.snapshot,
    required this.builder,
    this.empty,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 96),
    this.controller,
  });

  final Snapshot snapshot;
  final Widget Function(BuildContext context, dynamic data) builder;
  final Widget? empty;
  final EdgeInsetsGeometry padding;

  /// Supplied when the caller needs the scroll offset - the reader uses it to
  /// drive its progress line.
  final ScrollController? controller;

  @override
  State<SnapshotView> createState() => _SnapshotViewState();
}

class _SnapshotViewState extends State<SnapshotView> {
  @override
  void initState() {
    super.initState();
    widget.snapshot.hydrate().then((_) {
      if (mounted && widget.snapshot.value == null) {
        widget.snapshot.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.snapshot,
      builder: (context, _) {
        final snap = widget.snapshot;
        return RefreshIndicator(
          onRefresh: () => snap.refresh(),
          color: C.green,
          backgroundColor: C.surface,
          child: snap.value == null
              ? ListView(
                  controller: widget.controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: widget.padding,
                  children: [
                    if (snap.loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 120),
                        child: Center(child: MiniSpinner(size: 22)),
                      )
                    else if (snap.error != null)
                      ErrorRetry(snap.error!, onRetry: () => snap.refresh())
                    else
                      widget.empty ??
                          const EmptyState('Nothing here yet',
                              'Pull down to sync from the agent.'),
                  ],
                )
              : SingleChildScrollView(
                  controller: widget.controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: widget.padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (snap.error != null && snap.error != 'offline')
                        ErrorRetry(snap.error!,
                            onRetry: () => snap.refresh()),
                      widget.builder(context, snap.value),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// Bottom-sheet scaffold for forms; keyboard-safe, thumb-first.
Future<R?> showFormSheet<R>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Sz.rXl)),
      side: BorderSide(color: C.border),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: C.borderMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title, style: T.title),
              const SizedBox(height: 14),
              builder(ctx),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Confirmation dialog for destructive / gated actions.
Future<bool> confirmDialog(BuildContext context, String title, String body,
    {String action = 'Confirm', bool destructive = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: T.title),
      content: Text(body, style: T.body2),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: T.body2.copyWith(color: C.text3)),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: C.red)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return res ?? false;
}

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(
      children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            size: 16, color: error ? C.red : C.green),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
    duration: const Duration(seconds: 3),
  ));
}

/// Labelled text field with the dashboard's input styling.
class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.autofocus = false,
    this.obscure = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool autofocus;
  final bool obscure;
  final void Function(String)? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label.toUpperCase(),
              style: T.label.copyWith(letterSpacing: 0.6)),
        ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          autofocus: autofocus,
          obscureText: obscure,
          style: T.body2.copyWith(color: C.text),
          decoration: InputDecoration(hintText: hint),
          onSubmitted: onSubmitted,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Horizontal selector of options (status, priority...).
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final List<String> options;
  final String value;
  final void Function(String) onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label!.toUpperCase(),
                style: T.label.copyWith(letterSpacing: 0.6)),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final opt in options)
              Pill(opt, selected: opt == value, onTap: () => onChanged(opt)),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
