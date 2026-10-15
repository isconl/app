import 'package:flutter/material.dart';

import '../../services/documents.dart';
import '../widgets/documents_widgets.dart';

/// BI26100508: the console's documents and quill writer, split as the row asks:
/// the library first, then the studio that makes a new one.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, this.api});
  final DocumentsApi? api;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  GeneratedDoc? _reopen;
  int _library = 0;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(controller: _tabs, tabs: const [Tab(text: 'Documents'), Tab(text: 'New')]),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          DocumentsLibrary(
            key: ValueKey('lib$_library'),
            api: widget.api,
            onEdit: (d) {
              setState(() => _reopen = d);
              _tabs.animateTo(1);
            },
          ),
          DocumentStudio(
            key: ValueKey(_reopen?.id ?? 'new'),
            api: widget.api,
            reopen: _reopen,
            onGenerated: () => setState(() => _library++),
          ),
        ]),
      ),
    ]);
  }
}
