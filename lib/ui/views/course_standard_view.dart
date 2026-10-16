import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/markdown.dart';
import '../widgets/common.dart';

/// Summary page for the Course Standard ("what changed" section).
class CourseStandardView extends StatefulWidget {
  const CourseStandardView({super.key});

  @override
  State<CourseStandardView> createState() => _CourseStandardViewState();
}

class _CourseStandardViewState extends State<CourseStandardView> {
  String? _summary;
  bool _loading = false;

  static const _fallbackSummary = '''
# Course Standard v3.1

## What changed
- Declared Kind per block element replaces position-driven Lead/Support/Callout.
- Header line standardized: words, read time, reviewed date, and version.
- Navigation: dedicated study order with numbered courses.
- Standardized offline-first caching across learning modules.
''';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final learning = services.store.learning.value;
    if (learning is Map && fmt.s(learning['standardSummary']).isNotEmpty) {
      setState(() => _summary = fmt.s(learning['standardSummary']));
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await services.api.getJson('/api/learning/standard');
      if (!mounted) return;
      if (res is Map) {
        final text = fmt.s(res['whatChanged']).isNotEmpty
            ? fmt.s(res['whatChanged'])
            : (fmt.s(res['summary']).isNotEmpty
                ? fmt.s(res['summary'])
                : fmt.s(res['content']));
        if (text.isNotEmpty) {
          setState(() {
            _summary = text;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {
      // Offline or endpoint not yet deployed
    }
    if (!mounted) return;
    setState(() {
      _summary = _fallbackSummary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _summary == null) {
      return const Center(child: MiniSpinner(size: 22));
    }
    final text = _summary ?? _fallbackSummary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Markdown(text, variant: MarkdownVariant.reading),
      ],
    );
  }
}
