import 'package:flutter/material.dart';

import '../../theme.dart';
import '../widgets/common.dart';
import 'portfolio.dart';

/// BI26092324 (mobile twin of BI26092323's web row): Practice replaces
/// Portfolio as the Projects space's first tab. Documents is
/// [PortfolioView] unchanged (same `/api/portfolio` data/actions); every
/// other tab is an honest placeholder saying plainly it arrives with the
/// sconl-practice engine -- no faked numbers, matching
/// hub/web/static/app.js's renderPractice()/PRACTICE_TABS exactly, tab
/// for tab, so a later full build (BI26092652) lands on the same shape
/// both platforms already show.
enum _PracticeTab { documents, overview, practices, codex, enquiries }

const _practiceLater = ['Bookings', 'Orders', 'Newsletter', 'Portfolios'];
const _soon = 'Arrives when the sconl-practice engine is live.';

class PracticeView extends StatefulWidget {
  const PracticeView({super.key});

  @override
  State<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<PracticeView> {
  _PracticeTab _tab = _PracticeTab.documents;

  String _label(_PracticeTab t) => switch (t) {
        _PracticeTab.documents => 'Documents',
        _PracticeTab.overview => 'Overview',
        _PracticeTab.practices => 'Practices',
        _PracticeTab.codex => 'Codex',
        _PracticeTab.enquiries => 'Enquiries',
      };

  Widget _placeholder(String title) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: EmptyState(title, _soon),
      );

  Widget _overviewBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _placeholder('Overview'),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Also arriving with the engine', style: T.w600(T.body2)),
                const SizedBox(height: 6),
                Text(
                  '${_practiceLater.join(' · ')}: each ${_soon.toLowerCase()}',
                  style: T.small.copyWith(color: C.text3),
                ),
              ],
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Practice'),
        Text(
          "The Practice: Sconl's public platform and its own documents",
          style: T.small.copyWith(color: C.text3),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final t in _PracticeTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_label(t)),
                    selected: _tab == t,
                    onSelected: (_) => setState(() => _tab = t),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        switch (_tab) {
          _PracticeTab.documents => const PortfolioView(),
          _PracticeTab.overview => _overviewBody(),
          _ => _placeholder(_label(_tab)),
        },
      ],
    );
  }
}
