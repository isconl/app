import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../services/narration.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../../util/markdown.dart' show ChangeNote, changeNotesOf;
import 'common.dart';
import 'offline_narration.dart';
import 'reader_comfort.dart';

/// The listen control on a reading page.
///
/// Sits inside the reading measure and carries no border, because the reader is
/// borderless and a boxed control under borderless prose is the exact thing the
/// reading surface was built to remove.
///
/// It offers the device voice immediately - free, offline, every module - and
/// the agent's narration when one exists. It never offers a button that can only
/// fail: if the agent has no narration for this module it says "Have the agent
/// read it" and, if the module is plane B, it says so in those words after the
/// agent refuses, rather than showing an error.
class ListenBar extends StatefulWidget {
  const ListenBar({super.key, required this.course, required this.file, required this.markdown, this.padding = const EdgeInsets.only(top: 18, bottom: 2)});

  /// BI26111891: the module view sets its own even spacing around the row, with a divider under it.
  final EdgeInsetsGeometry padding;
  final String course;
  final String file;
  final String markdown;

  @override
  State<ListenBar> createState() => _ListenBarState();
}

class _ListenBarState extends State<ListenBar> {
  String get _key => Narrator.key(widget.course, widget.file);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final n = services.narrator;

    return ListenableBuilder(
      listenable: Listenable.merge([n, services.modules]),
      builder: (context, _) {
        final mine = n.current == _key;
        final audio = services.modules.audioFor(widget.course, widget.file);
        final hasNarration = audio?['available'] == true;
        final staleNarration = hasNarration && audio?['stale'] == true;

        return Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PrimaryButton(
                    active: mine && n.active,
                    loading: mine && n.busy,
                    label: mine && n.state == NarrationState.playing
                        ? 'Pause'
                        : mine && n.state == NarrationState.paused
                        ? 'Resume'
                        : 'Listen',
                    icon: mine && n.state == NarrationState.playing ? Icons.pause_rounded : Icons.headphones_rounded,
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      if (mine && n.state == NarrationState.playing) return n.pause();
                      if (mine && n.state == NarrationState.paused) return n.resume();
                      // Prefer the agent's voice when a current one exists;
                      // otherwise the device reads it now rather than later.
                      if (hasNarration && !staleNarration) {
                        await n.playAgent(
                          course: widget.course,
                          file: widget.file,
                          rev: fmt.s(audio?['rev']),
                          fallbackMarkdown: widget.markdown,
                        );
                      } else {
                        await n.speakDevice(course: widget.course, file: widget.file, markdown: widget.markdown);
                      }
                    },
                  ),
                  // BI26111599 (Sconl, 15 Nov 2026): speed (just "1x") and text size sit beside Listen; while it
                  // narrates, the skip and stop controls take the rest of this row.
                  const SizedBox(width: 8),
                  _ComfortButton(
                    key: const Key('listen-speed'),
                    tooltip: 'Narration speed',
                    onTap: () => showReaderComfortSheet(context),
                    child: Text(
                      speedLabel(Narrator.snapSpeed(n.speed)),
                      style: T.monoSmall.copyWith(color: C.text2, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ComfortButton(
                    key: const Key('reader-aa'),
                    tooltip: 'Text size and spacing',
                    onTap: () => showReaderComfortSheet(context),
                    child: Text('Aa', style: T.w600(T.body2).copyWith(color: C.text2)),
                  ),
                  // Sconl, 21 Nov 2026: what changed in this module, on every module, styled like speed and text size.
                  const SizedBox(width: 6),
                  _ComfortButton(
                    key: const Key('reader-changes'),
                    tooltip: 'What changed in this module',
                    onTap: () => showModuleChangesSheet(context, changeNotesOf(widget.markdown)),
                    child: Icon(Icons.history_rounded, size: 18, color: changeNotesOf(widget.markdown).isEmpty ? C.text3 : C.amber),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (mine && n.active && n.tier == NarrationTier.device && n.chunkCount > 0) ...[
                              IconButton(
                                key: const Key('listen-back'),
                                tooltip: 'Back a section',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.replay_rounded, size: 19),
                                onPressed: () => n.skip(-1),
                              ),
                              Text('${n.chunkIndex + 1}/${n.chunkCount}', style: T.monoSmall),
                              IconButton(
                                key: const Key('listen-forward'),
                                tooltip: 'Forward a section',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.forward_rounded, size: 19),
                                onPressed: () => n.skip(1),
                              ),
                            ],
                            if (mine && n.active)
                              IconButton(
                                key: const Key('listen-stop'),
                                tooltip: 'Stop',
                                visualDensity: VisualDensity.compact,
                                onPressed: n.stop,
                                icon: const Icon(Icons.stop_rounded, size: 19, color: C.text3),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // A seek bar only where there is something real to seek. The device
              // voice exposes no position, so faking a timeline for it would be a
              // lie the user can hear.
              if (mine && n.tier == NarrationTier.agent && n.duration > Duration.zero) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(fmt.clock(n.position), style: T.monoSmall),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: n.position.inMilliseconds.clamp(0, n.duration.inMilliseconds).toDouble(),
                          max: n.duration.inMilliseconds.toDouble(),
                          onChanged: (v) => n.seek(Duration(milliseconds: v.round())),
                        ),
                      ),
                    ),
                    Text(fmt.clock(n.duration), style: T.monoSmall),
                  ],
                ),
              ] else if (mine && n.tier == NarrationTier.device && n.chunkCount > 0) ...[
                const SizedBox(height: 8),
                // The device voice is read in chunks, so the line shows real progress; skipping is in the row above.
                LinearProgressIndicator(minHeight: 2, value: n.deviceProgress),
              ],

              if (hasNarration && !staleNarration && n.downloads != null)
                OfflineRow(
                  downloads: n.downloads!,
                  course: widget.course,
                  file: widget.file,
                  rev: fmt.s(audio?['rev']),
                ),
              if (staleNarration && !mine)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Narration exists but the module has changed since; Listen reads it on this device.',
                    key: const Key('listen-stale'),
                    style: T.tiny.copyWith(color: C.amber, fontSize: 11),
                  ),
                ),
              if (n.error != null && mine) ...[
                const SizedBox(height: 8),
                Text(
                  n.error!,
                  key: const Key('listen-error'),
                  style: T.tiny.copyWith(color: C.red),
                ),
                if (n.tier == NarrationTier.device)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('listen-retry'),
                      onPressed: () => n.retry(widget.markdown),
                      child: const Text('Try again'),
                    ),
                  ),
              ],
              if (mine && n.notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    n.notice!,
                    key: const Key('listen-notice'),
                    style: T.tiny.copyWith(color: C.amber),
                  ),
                ),
              if (mine && n.needsVoiceData)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No offline voice is installed. Open your phone settings, Text-to-speech output, '
                    'and install Google speech data for British English to listen without a signal.',
                    key: const Key('listen-voice-data'),
                    style: T.tiny.copyWith(color: C.amber),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.active,
    required this.loading,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final bool active;
  final bool loading;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      // BI26101804: a fully rounded pill.
      style: FilledButton.styleFrom(shape: const StadiumBorder()),
      onPressed: loading ? null : onTap,
      icon: loading ? const MiniSpinner() : Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _ComfortButton extends StatelessWidget {
  const _ComfortButton({super.key, required this.tooltip, required this.onTap, required this.child});
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: C.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
      ),
    );
  }
}


/// What changed in a module, newest first: each revision's date, what changed and why. A module with no change notes
/// says so, so the button behaves the same on every module.
Future<void> showModuleChangesSheet(BuildContext context, List<ChangeNote> notes) {
  final label = T.tiny.copyWith(color: C.text3, fontWeight: FontWeight.w700, letterSpacing: 0.9);
  final body = T.small.copyWith(color: C.text2, height: 1.5);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: ListView(
          key: const Key('module-changes-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('What changed', style: T.w600(T.body2)),
            const SizedBox(height: 12),
            if (notes.isEmpty)
              Text('No changes recorded since this module was published.', style: body)
            else
              for (var i = 0; i < notes.length; i++) ...[
                if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: C.border)),
                Text(notes[i].shortDate.toUpperCase(), style: label.copyWith(color: C.amber)),
                const SizedBox(height: 6),
                Text(notes[i].what, style: body),
                if (notes[i].why.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('WHY', style: label),
                  const SizedBox(height: 3),
                  Text(notes[i].why, style: body),
                ],
              ],
          ],
        ),
      ),
    ),
  );
}
