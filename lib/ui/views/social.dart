import 'package:flutter/material.dart';

import 'buffer.dart';

/// Social channels / Buffer desk view.
class SocialView extends StatelessWidget {
  const SocialView({super.key, this.compose = false});
  final bool compose;

  @override
  Widget build(BuildContext context) {
    return BufferView(compose: compose);
  }
}
