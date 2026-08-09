import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../services/narration.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import 'common.dart';

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
  const ListenBar({
    super.key,
    required this.course,
    required this.file,
    required this.markdown,
  });

  final String course;
  final String file;
  final String markdown;

  @override
  State<ListenBar> createState() => _ListenBarState();
}

class _ListenBarState extends State<ListenBar> {
  bool _requesting = false;
  String? _refusal;

  String get _key => Narrator.key(widget.course, widget.file);

  Future<void> _requestNarration() async {
    setState(() { _requesting = true; _refusal = null; });
    final services = AppScope.of(context);
    final reason = await services.narrator.requestNarration(widget.course, widget.file);
    if (!mounted) return;
    setState(() { _requesting = false; _refusal = reason; });
    if (reason == null) {
      await services.modules.check(force: true);
      if (!mounted) return;
      toast(context, 'Narration ready');
      await services.narrator.playAgent(course: widget.course, file: widget.file);
    }
  }

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
          padding: const EdgeInsets.only(top: 18, bottom: 2),
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
                    icon: mine && n.state == NarrationState.playing
                        ? Icons.pause_rounded
                        : Icons.headphones_rounded,
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      if (mine && n.state == NarrationState.playing) return n.pause();
                      if (mine && n.state == NarrationState.paused) return n.resume();
                      // Prefer the agent's voice when a current one exists;
                      // otherwise the device reads it now rather than later.
                      if (hasNarration && !staleNarration) {
                        await n.playAgent(course: widget.course, file: widget.file);
                      } else {
                        await n.speakDevice(
                          course: widget.course,
                          file: widget.file,
                          markdown: widget.markdown,
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mine && n.tier == NarrationTier.agent
                          ? 'The agent reading it'
                          : mine
                              ? 'This device reading it'
                              : hasNarration
                                  ? staleNarration
                                      ? 'Narration exists but the module has changed since'
                                      : 'Narrated by the agent'
                                  : 'This device can read it now, free and offline',
                      style: T.tiny.copyWith(
                          color: staleNarration ? C.amber : C.text3, fontSize: 11),
                    ),
                  ),
                  if (mine && n.active)
                    InkWell(
                      borderRadius: BorderRadius.circular(Sz.rSm),
                      onTap: n.stop,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.stop_rounded, size: 17, color: C.text3),
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
                          value: n.position.inMilliseconds
                              .clamp(0, n.duration.inMilliseconds)
                              .toDouble(),
                          max: n.duration.inMilliseconds.toDouble(),
                          onChanged: (v) =>
                              n.seek(Duration(milliseconds: v.round())),
                        ),
                      ),
                    ),
                    Text(fmt.clock(n.duration), style: T.monoSmall),
                  ],
                ),
              ] else if (mine && n.tier == NarrationTier.device)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),

              const SizedBox(height: 10),
              Row(
                children: [
                  Text('SPEED', style: T.label.copyWith(fontSize: 9.5)),
                  const SizedBox(width: 8),
                  for (final s in [0.9, 1.0, 1.15, 1.3, 1.5]) ...[
                    _SpeedChip(
                      value: s,
                      selected: (n.speed - s).abs() < 0.01,
                      onTap: () => n.setSpeed(s),
                    ),
                    const SizedBox(width: 5),
                  ],
                ],
              ),

              if (!hasNarration || staleNarration) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _requesting ? null : _requestNarration,
                    icon: _requesting
                        ? const MiniSpinner()
                        : const Icon(Icons.record_voice_over_rounded, size: 15),
                    label: Text(_requesting
                        ? 'The agent is reading it...'
                        : staleNarration
                            ? 'Re-record for the new version'
                            : 'Have the agent read it properly'),
                  ),
                ),
              ],

              if (_refusal != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_rounded, size: 13, color: C.amber),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        // Plane B is not an error. It is the system doing exactly
                        // what it exists to do, so it reads as a decision.
                        _refusal!.contains('plane')
                            ? 'This module stays on your devices. ${_refusal!} '
                                'The device voice above still reads it.'
                            : _refusal!,
                        style: T.tiny.copyWith(color: C.amber, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ],

              if (n.error != null && mine) ...[
                const SizedBox(height: 8),
                Text(n.error!, style: T.tiny.copyWith(color: C.red)),
              ],
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
      onPressed: loading ? null : onTap,
      icon: loading ? const MiniSpinner() : Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.value, required this.selected, required this.onTap});
  final double value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? C.greenBg : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? C.green : C.border),
        ),
        child: Text(
          // 1.0 reads as "1x", not "1.0x".
          value == value.roundToDouble() ? '${value.toInt()}x' : '${value}x',
          style: T.monoSmall.copyWith(
            color: selected ? C.greenBright : C.text3,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
