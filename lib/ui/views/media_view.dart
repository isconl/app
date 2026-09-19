import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../services/narration.dart';
import '../../theme.dart';
import '../../util/fmt.dart' as fmt;
import '../widgets/common.dart';

/// Media player and library view for audio narrations, local tracks, and streaming.
class MediaView extends StatelessWidget {
  const MediaView({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final narrator = services.narrator;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Now Playing'),
          _NowPlayingCard(narrator: narrator),
          const SizedBox(height: 14),
          const SectionLabel('Campus Audio Modules'),
          SnapshotView(
            snapshot: services.store.learning,
            builder: (context, data) {
              final courses = fmt.lm(fmt.m(data)['courses']);
              if (courses.isEmpty) {
                return const EmptyState(
                  'No audio modules ready',
                  'Narrations generated for campus courses appear here.',
                  icon: Icons.headphones_rounded,
                );
              }
              final items = <Widget>[];
              for (final c in courses) {
                final courseId = fmt.s(c['ID']);
                final lessons = fmt.lm(c['lessons']);
                for (final l in lessons) {
                  final file = fmt.s(l['file']);
                  final title = fmt.s(l['title']);
                  items.add(Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListenableBuilder(
                      listenable: narrator,
                      builder: (context, _) {
                        final thisKey = Narrator.key(courseId, file);
                        final isActive = narrator.current == thisKey && narrator.active;
                        return Panel(
                          onTap: () {
                            if (isActive) {
                              narrator.stop();
                            } else {
                              narrator.speakDevice(
                                course: courseId,
                                file: file,
                                markdown: title,
                              );
                            }
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                isActive ? Icons.stop_rounded : Icons.headphones_rounded,
                                size: 16,
                                color: isActive ? C.amber : C.greenBright,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: T.w500(T.body2)),
                                    Text(courseId, style: T.tiny),
                                  ],
                                ),
                              ),
                              if (isActive)
                                const Badge2('playing', color: Color(0x1FD29922), textColor: C.amber)
                              else
                                const Icon(Icons.play_circle_outline_rounded, size: 20, color: C.text3),
                            ],
                          ),
                        );
                      },
                    ),
                  ));
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.take(20).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.narrator});
  final Narrator narrator;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: narrator,
      builder: (context, _) {
        final current = narrator.current; // 'course/file' or null
        final String displayTitle = current != null
            ? current.split('/').last.replaceAll('.md', '').replaceAll('_', ' ')
            : 'No audio selected';
        final String displaySub = current != null
            ? current.split('/').first
            : 'Tap a module below to begin';
        final playing = narrator.active;

        return Panel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: C.surface,
                  borderRadius: BorderRadius.circular(Sz.rLg),
                  border: Border.all(color: playing ? C.greenDim : C.border),
                ),
                child: Icon(
                  playing ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                  size: 36,
                  color: playing ? C.greenBright : C.text3,
                ),
              ),
              const SizedBox(height: 14),
              Text(displayTitle, style: T.w600(T.headline), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(displaySub, style: T.body2, textAlign: TextAlign.center),
              if (narrator.duration.inSeconds > 0) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: narrator.duration.inMilliseconds > 0
                      ? narrator.position.inMilliseconds / narrator.duration.inMilliseconds
                      : 0.0,
                  backgroundColor: C.surface,
                  valueColor: const AlwaysStoppedAnimation(C.greenBright),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (playing)
                    IconButton.filled(
                      icon: const Icon(Icons.stop_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: C.amber,
                        foregroundColor: C.textInverse,
                        iconSize: 28,
                        padding: const EdgeInsets.all(12),
                      ),
                      onPressed: () => narrator.stop(),
                    )
                  else
                    IconButton.filled(
                      icon: const Icon(Icons.play_arrow_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: C.surface,
                        foregroundColor: C.text3,
                        iconSize: 28,
                        padding: const EdgeInsets.all(12),
                      ),
                      onPressed: null,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
