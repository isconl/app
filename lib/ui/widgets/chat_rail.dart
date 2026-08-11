import 'package:flutter/material.dart';

import '../../theme.dart';
import '../views/chat.dart';
import 'common.dart';

/// Persistent right-hand chat column for the desktop shell, matching
/// dashboard/style.css's always-visible `.chat-rail` (mobile only ever gets
/// chat as a modal sheet - see shell.dart's openChatSheet). The transcript
/// and composer are [ChatSheet] itself (embedded: true strips its modal-only
/// chrome) - not reimplemented here.
class ChatRail extends StatefulWidget {
  const ChatRail({super.key, this.width = 380});
  final double width;

  @override
  State<ChatRail> createState() => _ChatRailState();
}

class _ChatRailState extends State<ChatRail> {
  int _mode = 1; // 0 Context, 1 Chat, 2 Reader

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      decoration: const BoxDecoration(
        color: C.panel,
        border: Border(left: BorderSide(color: C.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _ModeBar(mode: _mode, onChange: (m) => setState(() => _mode = m)),
          ),
          Expanded(
            child: switch (_mode) {
              0 => const EmptyState(
                  'Context',
                  "Not wired up yet in the web console.",
                  icon: Icons.info_outline_rounded,
                ),
              2 => const EmptyState(
                  'Reader',
                  "Document preview isn't wired up yet in the web console.",
                  icon: Icons.menu_book_rounded,
                ),
              _ => const ChatSheet(embedded: true),
            },
          ),
        ],
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.mode, required this.onChange});
  final int mode;
  final void Function(int) onChange;

  static const _labels = ['Context', 'Chat', 'Reader'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 8),
              child: Center(
                child: Pill(_labels[i],
                    selected: i == mode, onTap: () => onChange(i)),
              ),
            ),
          ),
      ],
    );
  }
}
