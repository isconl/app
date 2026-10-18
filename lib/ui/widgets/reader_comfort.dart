import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/narration.dart';
import '../../theme.dart';
import '../../util/reader_prefs.dart';

/// BI26100141, BI26101804: narration speed, text size, line spacing and focus mode in ONE centred dialog. It opens from
/// the speed button and from `Aa`, both under Listen. Changes apply live and are remembered; the speed is one of three.
Future<void> showReaderComfortSheet(BuildContext context) {
  final services = AppScope.of(context);
  final db = services.db;
  final narrator = services.narrator;
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: C.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sz.rXl),
        side: const BorderSide(color: C.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: Listenable.merge([ReaderPrefs.instance, narrator]),
            builder: (ctx, _) {
              final p = ReaderPrefs.instance;
              return Padding(
                key: const Key('reader-comfort-dialog'),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NARRATION SPEED', style: T.label),
                    const SizedBox(height: 8),
                    SegmentedButton<double>(
                      key: const Key('speed-segments'),
                      showSelectedIcon: false,
                      segments: [
                        for (final s in Narrator.speeds)
                          ButtonSegment<double>(value: s, label: Text(speedLabel(s), key: Key('speed-$s'))),
                      ],
                      selected: {Narrator.snapSpeed(narrator.speed)},
                      onSelectionChanged: (v) => narrator.setSpeed(v.first),
                    ),
                    const SizedBox(height: 16),
                    Text('TEXT SIZE', style: T.label),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 0; i < ReaderPrefs.sizeLabels.length; i++)
                          ChoiceChip(
                            key: Key('size-${ReaderPrefs.sizeLabels[i]}'),
                            label: Text(ReaderPrefs.sizeLabels[i]),
                            selected: p.sizeStep == i,
                            onSelected: (_) => p.update(size: i, db: db),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('LINE SPACING', style: T.label),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          key: const Key('spacing-normal'),
                          label: const Text('Normal'),
                          selected: !p.relaxed,
                          onSelected: (_) => p.update(relaxed: false, db: db),
                        ),
                        ChoiceChip(
                          key: const Key('spacing-relaxed'),
                          label: const Text('Relaxed'),
                          selected: p.relaxed,
                          onSelected: (_) => p.update(relaxed: true, db: db),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      key: const Key('focus-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('Focus mode', style: T.body2),
                      subtitle: Text('Hide the bar and buttons while you scroll down', style: T.tiny),
                      value: p.focus,
                      onChanged: (v) => p.update(focus: v, db: db),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const Key('reader-comfort-done'),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// 1.0 reads "1×", 1.25 "1.25×", 1.5 "1.5×".
String speedLabel(double v) => v == v.roundToDouble() ? '${v.toInt()}×' : '$v×';
