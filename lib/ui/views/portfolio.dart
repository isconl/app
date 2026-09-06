import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// BN26090606: Sconl's own curated CVs/resumes/portfolio-document links --
/// always the latest version, a simple link list (Phase 1, per the
/// webconsole's own "a live, public-facing portfolio product is a future
/// build, not this" note). Ported from renderPortfolio()/portfolioAdd()/
/// portfolioRemove() (`hub/web/static/app.js`) -- same `/api/portfolio`
/// GET (list) / POST (whole-list save) shape, not a new backend feature.
///
/// This is the Projects tab's hub-style sub, the tab's own top-level
/// screen -- it was previously (incorrectly) `ProjectsView(cat: 'portfolio')`,
/// a venture-category filter that was never the real Portfolio feature and
/// will always be empty besides (every venture's CATEGORY is unpopulated,
/// see BN26090610).
class PortfolioView extends StatefulWidget {
  const PortfolioView({super.key});

  @override
  State<PortfolioView> createState() => _PortfolioViewState();
}

class _PortfolioViewState extends State<PortfolioView> {
  final _title = TextEditingController();
  final _url = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    final services = AppScope.of(context);
    setState(() => _saving = true);
    try {
      await services.api.postJson('/api/portfolio', {'items': items});
      await services.store.portfolio.refresh();
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _add(List<Map<String, dynamic>> current) async {
    final title = _title.text.trim();
    final url = _url.text.trim();
    if (title.isEmpty || url.isEmpty) {
      toast(context, 'Title and link are both required', error: true);
      return;
    }
    await _save([...current, {'title': title, 'url': url}]);
    _title.clear();
    _url.clear();
  }

  Future<void> _remove(List<Map<String, dynamic>> current, int idx) async {
    final items = [...current]..removeAt(idx);
    await _save(items);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SnapshotView(
      snapshot: services.store.portfolio,
      builder: (context, data) {
        final items = fmt.lm(fmt.m(data)['items']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Portfolio'),
            Text(
              "Sconl's own CVs, resumes, and portfolio documents - always the latest version",
              style: T.small.copyWith(color: C.text3),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const EmptyState('Nothing added yet',
                  'Add a link below - a resume, CV, or document.')
            else
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PortfolioTile(
                    item: items[i],
                    onRemove: _saving ? null : () => _remove(items, i),
                  ),
                ),
            const SizedBox(height: 12),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                        hintText: 'Title, e.g. Resume 2026'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _url,
                    decoration: const InputDecoration(
                        hintText: 'Live document link (OneDrive/Google)'),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _saving ? null : () => _add(items),
                    child: Text(_saving ? 'Saving…' : 'Add'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PortfolioTile extends StatelessWidget {
  const _PortfolioTile({required this.item, required this.onRemove});
  final Map<String, dynamic> item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final url = fmt.s(item['url']);
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: url.isEmpty
          ? null
          : () {
              final uri = Uri.tryParse(url);
              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmt.s(item['title']), style: T.w600(T.body2)),
                if (fmt.s(item['note']).isNotEmpty)
                  Text(fmt.s(item['note']), style: T.small.copyWith(color: C.text3)),
                if (url.isNotEmpty)
                  Text(url, style: T.monoSmall.copyWith(color: C.cyan),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: C.text3),
              onPressed: onRemove,
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}
