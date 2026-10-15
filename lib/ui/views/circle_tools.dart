import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/circle_depth.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/circle_depth_widgets.dart';
import 'circle.dart' show PersonScreen;

/// BI26100507: the Circle's depth that is not about one person: tags, who can, the
/// gallery, chat archive import and the circle-wide read. Each tab talks to the
/// reader's own hub only.
class CircleToolsScreen extends StatelessWidget {
  const CircleToolsScreen({super.key, this.api, this.onOpenPerson});
  final CircleDepthApi? api;

  /// Opens a person by id; the app finds them in the Circle snapshot.
  final void Function(BuildContext context, String personId)? onOpenPerson;

  static void _openPerson(BuildContext context, String id) {
    final people = fmt.lm(fmt.m(AppScope.of(context).store.circle.value)['people']);
    final person = people.firstWhere((p) => fmt.s(p['ID']) == id, orElse: () => const <String, dynamic>{});
    if (person.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PersonScreen(person: person)));
  }

  @override
  Widget build(BuildContext context) {
    void open(String id) => (onOpenPerson ?? _openPerson)(context, id);
    return DefaultTabController(
      length: 5,
      child: Column(children: [
        const TabBar(isScrollable: true, tabs: [
          Tab(text: 'Tags'),
          Tab(text: 'Who can'),
          Tab(text: 'Gallery'),
          Tab(text: 'Import'),
          Tab(text: 'Read'),
        ]),
        Expanded(
          child: TabBarView(children: [
            TagsManager(api: api, onChanged: () => AppScope.of(context).store.circle.refresh()),
            WhoCanView(api: api, onOpen: open),
            CircleGalleryView(api: api),
            ChatImportView(api: api, onOpen: open),
            CircleAnalysisView(api: api),
          ]),
        ),
      ]),
    );
  }
}
