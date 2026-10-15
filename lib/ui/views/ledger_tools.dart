import 'package:flutter/material.dart';

import '../../services/ledger_tools.dart';
import '../../theme.dart';
import '../widgets/ledger_widgets.dart';
import 'personal_dashboard.dart' show Unlock, deviceUnlock;

/// BI26100509: accounts, goals, income, the review queue, the report and possessions and ventures. All T3: nothing
/// loads until the device confirms it is the reader, and it locks again when the screen is left or the app goes to
/// the background. No figure is fetched while locked.
class LedgerToolsScreen extends StatefulWidget {
  const LedgerToolsScreen({super.key, this.api, this.unlock = deviceUnlock});
  final LedgerApi? api;
  final Unlock unlock;

  @override
  State<LedgerToolsScreen> createState() => _LedgerToolsScreenState();
}

class _LedgerToolsScreenState extends State<LedgerToolsScreen> with WidgetsBindingObserver {
  bool _open = false;
  bool _asking = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_open) setState(() => _open = false);
    }
  }

  Future<void> _unlock() async {
    setState(() {
      _asking = true;
      _note = null;
    });
    final ok = await widget.unlock();
    if (!mounted) return;
    setState(() {
      _asking = false;
      _open = ok;
      if (!ok) _note = 'Not unlocked.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline_rounded, size: 36, color: C.text3),
            const SizedBox(height: 10),
            Text('The ledger is private', style: T.title),
            const SizedBox(height: 4),
            Text('Unlock with this device to see and change your accounts, income and assets.', textAlign: TextAlign.center, style: T.small),
            if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, key: const Key('ledger-locked-note'), style: T.small)),
            const SizedBox(height: 12),
            FilledButton(key: const Key('ledger-unlock'), onPressed: _asking ? null : _unlock, child: const Text('Unlock')),
          ]),
        ),
      );
    }
    return DefaultTabController(
      length: 5,
      child: Column(children: [
        const TabBar(isScrollable: true, tabs: [
          Tab(text: 'Accounts'),
          Tab(text: 'Income'),
          Tab(text: 'Review'),
          Tab(text: 'Report'),
          Tab(text: 'Assets'),
        ]),
        Expanded(
          child: TabBarView(children: [
            AccountsTab(api: widget.api),
            IncomeTab(api: widget.api),
            ReviewTab(api: widget.api),
            ReportTab(api: widget.api),
            AssetsTab(api: widget.api),
          ]),
        ),
      ]),
    );
  }
}
