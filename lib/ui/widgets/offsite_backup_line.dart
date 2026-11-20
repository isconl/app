import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;

/// What the offsite backup line says and which colour it takes (BI26100503).
class BackupLineView {
  const BackupLineView(this.text, this.color);
  final String text;
  final Color color;
}

String _age(num hours) {
  if (hours < 1) return 'under 1 h ago';
  if (hours < 48) return '${hours.round()} h ago';
  return '${(hours / 24).round()} days ago';
}

/// The line for `GET /api/vitals/backup`. Green only for a clean green answer under 24 hours old; red with
/// the server's reason once it is past that or the server says red; grey, never green, for anything else:
/// no answer, a failed call, an unknown status, or a green with no age.
BackupLineView backupLineView(dynamic answer, {String? error}) {
  final v = fmt.m(answer);
  final status = fmt.s(v['status']);
  final reason = fmt.s(v['reason']).trim();
  final hours = v['age_hours'] is num ? v['age_hours'] as num : null;
  if (status == 'green' && hours != null && hours < 24) {
    return BackupLineView('Offsite backup: ${_age(hours)}', C.green);
  }
  if (status == 'red' || (status == 'green' && hours != null)) {
    final when = hours == null ? '' : ' ${_age(hours)}';
    final why = reason.isEmpty ? '' : ', $reason';
    return BackupLineView('Offsite backup:$when$why', C.red);
  }
  final why = reason.isNotEmpty ? reason : (error != null ? 'could not be reached' : 'no answer yet');
  return BackupLineView('Offsite backup: unknown ($why)', C.text3);
}

/// One line on Today: how old the newest offsite backup copy is.
class OffsiteBackupLine extends StatefulWidget {
  const OffsiteBackupLine({super.key});

  @override
  State<OffsiteBackupLine> createState() => _OffsiteBackupLineState();
}

class _OffsiteBackupLineState extends State<OffsiteBackupLine> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = AppScope.of(context).store.backupOffsite;
      s.hydrate().then((_) {
        if (mounted) s.refresh();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = AppScope.of(context).store.backupOffsite;
    return ListenableBuilder(
      listenable: snap,
      builder: (context, _) {
        final line = backupLineView(snap.value, error: snap.error);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: line.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(line.text, key: const Key('offsite-backup-line'), style: T.small.copyWith(color: line.color))),
            ],
          ),
        );
      },
    );
  }
}
