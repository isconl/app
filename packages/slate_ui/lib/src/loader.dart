import 'package:flutter/material.dart';

import 'tokens.dart';

/// Loads once, offers pull to refresh, and says plainly when slate did not
/// answer. Shared by every list screen.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    final d = _data;
    if (d == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Text('Could not reach slate.', style: TextStyle(color: t.danger)),
      );
    }
    return widget.builder(context, d, _reload);
  }
}

/// A small uppercase section label.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: SlateTokens.of(context).text3,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
      );
}

/// One row tile: id, title, and the small facts under it.
class RowTile extends StatelessWidget {
  const RowTile({super.key, required this.id, required this.title, required this.meta, this.onTap});
  final String id;
  final String title;
  final String meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = SlateTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.hairline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(id,
              style: TextStyle(
                  color: t.accent,
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.text, fontSize: 13)),
          const SizedBox(height: 4),
          Text(meta, style: TextStyle(color: t.text3, fontSize: 11)),
        ]),
      ),
    );
  }
}
