import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/status.dart';

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String dateTimeText(BuildContext context, DateTime? t) => t == null ? '–' : DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).add_Hm().format(t);
String kg(num? v) => v == null ? '–' : '${NumberFormat.decimalPattern('en_IN').format(v.round())} kg';

/// Runs a server call, shows its error (or [success]) in a snackbar. Returns true when it worked.
Future<bool> runAndReport(BuildContext context, Future<void> Function() call, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await call();
    if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
    return true;
  } on AppException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: context.mounted ? context.palette.critical : null));
    return false;
  }
}

Future<bool> confirm(BuildContext context, String title, {String? body, String? ok, bool danger = false}) async {
  final l = context.l10n;
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: body == null ? null : Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
            FilledButton(
              key: const Key('confirm-ok'),
              style: danger ? FilledButton.styleFrom(backgroundColor: c.palette.critical, foregroundColor: c.palette.onStatus(c.palette.critical)) : null,
              onPressed: () => Navigator.pop(c, true),
              child: Text(ok ?? l.ok),
            ),
          ],
        ),
      ) ??
      false;
}

StatusLevel alertLevel(String? severity, String? status) =>
    status == 'RESOLVED' ? StatusLevel.safe : severity == 'CRITICAL' ? StatusLevel.critical : severity == 'WARNING' ? StatusLevel.watch : StatusLevel.info;

StatusLevel tripLevel(String? status) => switch (status) {
      'IN_PROGRESS' => StatusLevel.info,
      'COMPLETED' => StatusLevel.safe,
      'CANCELLED' => StatusLevel.critical,
      _ => StatusLevel.watch,
    };

/// A KPI tile (Section 10.6 #1): value, label, icon; tapping opens the related list.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, required this.icon, this.level, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final StatusLevel? level;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        status: level,
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: level == null ? context.tokens.flavorAccent : context.palette.status(level!)),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: AppTypography.metric.copyWith(color: context.palette.textPrimary)),
          Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
        ]),
      );
}

/// Width-aware grid of cards: 2 columns on a phone, up to 5 on a wide screen.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.minWidth = 160});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = (box.maxWidth / minWidth).floor().clamp(1, children.length.clamp(1, 5));
        final w = (box.maxWidth - AppSpacing.sm * (cols - 1)) / cols;
        return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [for (final c in children) SizedBox(width: w, child: c)]);
      });
}

/// A card heading with a status chip: wraps under the title when the text is large (a Row
/// overflowed at text scale 2.0, M13 test).
class TitleChip extends StatelessWidget {
  const TitleChip({super.key, required this.title, required this.chip});
  final String title;
  final Widget chip;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        chip,
      ]);
}

/// A titled section with an optional action.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.sm, children: [Text(title, style: Theme.of(context).textTheme.titleMedium), ?action]),
          const SizedBox(height: AppSpacing.sm),
          child,
        ]),
      );
}

/// Two panes side by side on a wide screen (list | detail), stacked on a phone (Section 10.6).
class TwoPane extends StatelessWidget {
  const TwoPane({super.key, required this.left, required this.right, this.leftFlex = 2, this.rightFlex = 3});
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 900
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: leftFlex, child: left), const SizedBox(width: AppSpacing.lg), Expanded(flex: rightFlex, child: right)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: AppSpacing.lg), right]),
      );
}

/// One text input of [TextFieldsDialog].
class DialogField {
  const DialogField(this.key, this.label, {this.initial = '', this.hint, this.keyboardType, this.suffix, this.maxLines = 1});
  final String key;
  final String label;
  final String initial;
  final String? hint;
  final TextInputType? keyboardType;
  final String? suffix;
  final int maxLines;
}

/// A dialog that owns its controllers: they are disposed with the dialog, after its exit
/// animation (disposing them when `showDialog` returns crashed the closing dialog — M13 test).
/// Pops a map field key → text, or [extraValue] for the extra action, or null on cancel.
class TextFieldsDialog extends StatefulWidget {
  const TextFieldsDialog({super.key, required this.title, required this.fields, required this.saveLabel, this.extra, this.extraLabel, this.extraValue});
  final String title;
  final List<DialogField> fields;
  final String saveLabel;
  final Widget Function(BuildContext context)? extra;
  final String? extraLabel;
  final Map<String, String>? extraValue;

  @override
  State<TextFieldsDialog> createState() => _TextFieldsDialogState();
}

class _TextFieldsDialogState extends State<TextFieldsDialog> {
  late final _c = {for (final f in widget.fields) f.key: TextEditingController(text: f.initial)};

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: TextField(
                  key: Key(f.key),
                  controller: _c[f.key],
                  keyboardType: f.keyboardType,
                  maxLines: f.maxLines,
                  minLines: 1,
                  decoration: InputDecoration(labelText: f.label, hintText: f.hint, suffixText: f.suffix),
                ),
              ),
            if (widget.extra != null) widget.extra!(context),
          ]),
        ),
        actions: [
          if (widget.extraLabel != null) TextButton(onPressed: () => Navigator.pop(context, widget.extraValue), child: Text(widget.extraLabel!)),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.cancel)),
          FilledButton(key: Key('${widget.fields.first.key}-save'), onPressed: () => Navigator.pop(context, {for (final e in _c.entries) e.key: e.value.text}), child: Text(widget.saveLabel)),
        ],
      );
}
