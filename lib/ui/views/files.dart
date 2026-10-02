import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/client.dart';
import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/markdown.dart';
import '../widgets/common.dart';

/// The OneDrive mirror, browsable from the phone.
///
/// Listings are cached per folder, so a folder visited once still opens with no
/// connection. Content is not: a file preview is a live read, because a stale
/// document shown as current is worse than an honest "offline".
class FilesView extends StatefulWidget {
  const FilesView({super.key, this.initialPath = 'root'});
  final String initialPath;

  @override
  State<FilesView> createState() => _FilesViewState();
}

class _FilesViewState extends State<FilesView> {
  late List<String> _stack = [widget.initialPath];

  String get _path => _stack.last;

  void _open(String name) {
    setState(() {
      _stack = [..._stack, _path == 'root' ? name : '$_path/$name'];
    });
  }

  bool _up() {
    if (_stack.length <= 1) return false;
    setState(() => _stack = _stack.sublist(0, _stack.length - 1));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final snapshot = services.store.folder(_path);

    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Breadcrumb(
            stack: _stack,
            onJump: (idx) => setState(() => _stack = _stack.sublist(0, idx + 1)),
          ),
          Expanded(
            child: SnapshotView(
              snapshot: snapshot,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
              builder: (context, data) {
                final map = fmt.m(data);
                final error = fmt.s(map['error']);
                final items = fmt.lm(map['items']);
                // Folders first, then files; alphabetical inside each group.
                final sorted = [...items]..sort((a, b) {
                    final fa = fmt.b(a['isFolder']) ? 0 : 1;
                    final fb = fmt.b(b['isFolder']) ? 0 : 1;
                    if (fa != fb) return fa - fb;
                    return fmt
                        .s(a['name'])
                        .toLowerCase()
                        .compareTo(fmt.s(b['name']).toLowerCase());
                  });

                if (error.isNotEmpty && items.isEmpty) {
                  return ErrorRetry(error, onRetry: () => snapshot.refresh());
                }
                if (sorted.isEmpty) {
                  return const EmptyState(
                    'Empty folder',
                    'Nothing here in the OneDrive mirror.',
                    icon: Icons.folder_open_rounded,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in sorted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _ItemTile(
                          item: item,
                          onTap: () {
                            if (fmt.b(item['isFolder'])) {
                              _open(fmt.s(item['name']));
                            } else {
                              _fileSheet(context, item);
                            }
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fileSheet(BuildContext context, Map<String, dynamic> item) {
    return showFormSheet(
      context,
      title: fmt.truncate(fmt.s(item['name']), 60),
      builder: (ctx) => _FileSheet(item: item),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.stack, required this.onJump});
  final List<String> stack;
  final void Function(int) onJump;

  @override
  Widget build(BuildContext context) {
    String label(String p) =>
        p == 'root' ? 'OneDrive' : p.split('/').last;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: [
            for (var idx = 0; idx < stack.length; idx++) ...[
              if (idx > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 14, color: C.text3),
                ),
              InkWell(
                onTap: idx == stack.length - 1 ? null : () => onJump(idx),
                child: Text(
                  label(stack[idx]),
                  style: T.small.copyWith(
                    color: idx == stack.length - 1 ? C.greenBright : C.text3,
                    fontWeight: idx == stack.length - 1
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static IconData _icon(String name, bool folder) {
    if (folder) return Icons.folder_rounded;
    final ext = name.toLowerCase().split('.').last;
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf_rounded;
    if (['doc', 'docx', 'odt'].contains(ext)) return Icons.description_rounded;
    if (['xls', 'xlsx', 'csv', 'tsv'].contains(ext)) return Icons.table_chart_rounded;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_rounded;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return Icons.folder_zip_rounded;
    if (['md', 'markdown', 'txt', 'rst'].contains(ext)) return Icons.article_rounded;
    if (['mp4', 'mov', 'mkv', 'avi'].contains(ext)) return Icons.movie_rounded;
    if (['mp3', 'wav', 'm4a', 'aac'].contains(ext)) return Icons.audiotrack_rounded;
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final folder = fmt.b(item['isFolder']);
    final name = fmt.s(item['name']);
    final children = fmt.i(item['childCount']);
    final meta = folder
        ? (children > 0 ? fmt.plural(children, 'item') : 'empty')
        : [
            fmt.bytesLabel(item['size']),
            fmt.ago(item['lastModifiedDateTime']),
          ].where((v) => v.isNotEmpty).join(' · ');

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          Icon(_icon(name, folder),
              size: 18, color: folder ? C.cyan : C.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: T.w500(T.body2.copyWith(color: C.text)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (meta.isNotEmpty)
                  Text(meta, style: T.monoSmall),
              ],
            ),
          ),
          Icon(
              folder
                  ? Icons.chevron_right_rounded
                  : Icons.more_horiz_rounded,
              size: 16,
              color: C.text3),
        ],
      ),
    );
  }
}

/// File detail: metadata always, text preview when the agent can produce one.
class _FileSheet extends StatefulWidget {
  const _FileSheet({required this.item});
  final Map<String, dynamic> item;

  @override
  State<_FileSheet> createState() => _FileSheetState();
}

class _FileSheetState extends State<_FileSheet> {
  bool _loading = false;
  String? _text;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final webUrl = fmt.s(item['webUrl']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KvRow('Size', fmt.bytesLabel(item['size'])),
        KvRow('Modified', fmt.shortDate(item['lastModifiedDateTime'])),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _preview,
              icon: _loading
                  ? const MiniSpinner()
                  : const Icon(Icons.visibility_rounded, size: 16),
              label: const Text('Preview'),
            ),
            if (webUrl.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(webUrl),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open in OneDrive'),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorRetry(_error!, onRetry: _preview),
        ],
        if (_text != null) ...[
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxHeight: 380),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: C.bgRaised,
              border: Border.all(color: C.border),
              borderRadius: BorderRadius.circular(Sz.rMd),
            ),
            child: SingleChildScrollView(
              child: Markdown(_text!),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _preview() async {
    final services = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await services.api.getJson(
          '/api/onedrive/preview?id=${Uri.encodeQueryComponent(fmt.s(widget.item['id']))}');
      final map = fmt.m(res);
      final text = fmt.s(map['textContent']);
      if (!mounted) return;
      setState(() {
        if (text.isNotEmpty) {
          _text = text;
        } else {
          _error = fmt.b(map['isText'])
              ? 'The agent could not read this file back.'
              : 'No text preview for this type - open it in OneDrive.';
        }
      });
    } on OfflineException {
      if (mounted) setState(() => _error = 'offline');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
