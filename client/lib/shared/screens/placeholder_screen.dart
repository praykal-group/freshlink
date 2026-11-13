import 'package:flutter/material.dart';

/// Temporary home screen used by every flavor until its real screens land (M11–M13).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, required this.moduleTag});

  final String title;
  final String moduleTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(moduleTag, key: const Key('module-tag'))),
    );
  }
}
