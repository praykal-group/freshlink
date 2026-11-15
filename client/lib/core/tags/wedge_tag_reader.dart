import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/app_spacing.dart';
import 'tag_reader.dart';

/// Collects keystrokes from a keyboard-wedge reader (UHF handheld over Bluetooth HID): characters
/// arrive fast and end with Enter. Typing by hand also works. Pure, so it is unit-tested.
class WedgeBuffer {
  WedgeBuffer({this.maxGap = const Duration(milliseconds: 300)});
  final Duration maxGap;
  final _chars = StringBuffer();
  DateTime? _last;

  /// Feed one character (or a pasted chunk). A long pause starts a new read.
  void add(String chars, DateTime at) {
    if (_last != null && at.difference(_last!) > maxGap) _chars.clear();
    _chars.write(chars);
    _last = at;
  }

  /// Enter pressed: returns the normalised value (null if not a valid tag) and resets.
  String? submit() {
    final v = normaliseTagValue(TagKind.uhf, _chars.toString());
    _chars.clear();
    _last = null;
    return v;
  }
}

class WedgeTagReader implements TagReader {
  const WedgeTagReader();

  @override
  TagKind get kind => TagKind.uhf;

  @override
  Future<TagRead?> read(BuildContext context) => showModalBottomSheet<TagRead>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _WedgeSheet(),
      );
}

class _WedgeSheet extends StatefulWidget {
  const _WedgeSheet();

  @override
  State<_WedgeSheet> createState() => _WedgeSheetState();
}

class _WedgeSheetState extends State<_WedgeSheet> {
  final _c = TextEditingController();
  String? _error;

  void _done(String value) {
    final v = normaliseTagValue(TagKind.uhf, value);
    if (v == null) {
      setState(() => _error = context.l10n.tagInvalid);
      return;
    }
    Navigator.pop(context, TagRead(TagKind.uhf, v));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.tagWedgeTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(l.tagWedgeHelp),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const Key('wedge-input'),
          controller: _c,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9:_\- ]'))],
          textInputAction: TextInputAction.done,
          onSubmitted: _done,
          decoration: InputDecoration(hintText: 'E200 3412 0123 4567 8901 2345', errorText: _error),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(onPressed: () => _done(_c.text), child: Text(l.ok)),
      ]),
    );
  }
}
