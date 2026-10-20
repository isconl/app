import 'package:flutter/material.dart';

import '../../theme.dart';
import '../widgets/common.dart';
import '../../app_scope.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/space_header.dart';
import 'portfolio.dart';
import 'practice_leads.dart';
import 'projects_dash_model.dart';
import 'projects_dashboard.dart';

/// BI26092324 (mobile twin of BI26092323's web row): Practice replaces
/// Portfolio as the Projects space's first tab. Documents is
/// [PortfolioView] unchanged (same `/api/portfolio` data/actions); every
/// other tab is an honest placeholder saying plainly it arrives with the
/// sconl-practice engine -- no faked numbers, matching
/// hub/web/static/app.js's renderPractice()/PRACTICE_TABS exactly, tab
/// for tab, so a later full build (BI26092652) lands on the same shape
/// both platforms already show.
const _practiceLater = ['Bookings', 'Orders', 'Newsletter', 'Portfolios'];
const _soon = 'Arrives when the sconl-practice engine is live.';

/// BI26101815: Practice is Overview (the dashboard tiles and what is still to arrive), Documents and Enquiries.
const practiceTabLabels = ['Overview', 'Documents', 'Enquiries'];

class PracticeView extends StatelessWidget {
  const PracticeView({super.key, this.onOpenSub});

  /// Opens a sibling Projects sub-tab (Corporate 1, Products 2, Platforms 3).
  final void Function(int sub)? onOpenSub;

  /// The search finds a document and opens the Documents tab. Enquiries are fetched live by their own tab, so they are
  /// searched there.
  static List<SpaceHit> hitsFor(BuildContext context) => [
        for (final i in fmt.lm(fmt.m(AppScope.of(context).store.portfolio.value)['items']))
          if (fmt.s(i['title']).isNotEmpty) SpaceHit(title: fmt.s(i['title']), subtitle: fmt.s(i['url']), tab: 1),
      ];

  Widget _later() => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Also arriving with the engine', style: T.w600(T.body2)),
            const SizedBox(height: 6),
            Text(
              'Practices and Codex, then ${_practiceLater.join(' · ')}: each ${_soon.toLowerCase()}',
              style: T.small.copyWith(color: C.text3),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SpaceView(
      space: 'practice',
      searchHint: 'Search documents and enquiries',
      subtitle: "The Practice: Sconl's public platform and its own documents",
      hits: hitsFor,
      tabs: [
        SpaceTab(
          practiceTabLabels[0],
          SnapshotView(
            snapshot: AppScope.of(context).store.projects,
            builder: (context, data) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ProjectsDashboard(dash: ProjectsDash.from(fmt.lm(fmt.m(data)['projects'])), onOpenSub: onOpenSub),
              const SizedBox(height: 12),
              _later(),
            ]),
          ),
        ),
        SpaceTab(practiceTabLabels[1], const PortfolioView()),
        SpaceTab(practiceTabLabels[2], const SingleChildScrollView(child: PracticeLeads())),
      ],
    );
  }
}
