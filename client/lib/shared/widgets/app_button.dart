import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';

enum AppButtonKind { primary, tonal, outlined, danger }

/// Section 13.3 buttons: filled primary for the one main action, tonal secondary, outlined
/// tertiary, red filled only for SOS / Reject. Height 52 (56 in driver/operator), press scale 0.97.
class AppButton extends StatefulWidget {
  const AppButton({super.key, required this.label, required this.onPressed, this.kind = AppButtonKind.primary, this.icon, this.busy = false, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;

  /// Shows a spinner and ignores taps (e.g. while sending the OTP).
  final bool busy;
  final bool expand;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = t.palette;
    final enabled = widget.onPressed != null && !widget.busy;
    final child = widget.busy
        ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.kind == AppButtonKind.primary || widget.kind == AppButtonKind.danger ? p.onPrimary : p.primary))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[Icon(widget.icon, size: 22), const SizedBox(width: AppSpacing.sm)],
            Flexible(child: Text(widget.label, textAlign: TextAlign.center, softWrap: true)),
          ]);
    final onPressed = enabled ? widget.onPressed : null;
    final min = Size(widget.expand ? double.infinity : 64, t.buttonHeight);
    final Widget button = switch (widget.kind) {
      AppButtonKind.primary => FilledButton(onPressed: onPressed, style: FilledButton.styleFrom(minimumSize: min), child: child),
      AppButtonKind.tonal => FilledButton.tonal(onPressed: onPressed, style: FilledButton.styleFrom(minimumSize: min), child: child),
      AppButtonKind.outlined => OutlinedButton(onPressed: onPressed, style: OutlinedButton.styleFrom(minimumSize: min), child: child),
      AppButtonKind.danger => FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(minimumSize: min, backgroundColor: p.critical, foregroundColor: p.onStatus(p.critical)),
          child: child,
        ),
    };
    final scale = AppMotion.reduced(context) || !_down ? 1.0 : AppMotion.pressScale;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.busy ? widget.label : null,
      child: Listener(
        onPointerDown: enabled ? (_) => setState(() => _down = true) : null,
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(scale: scale, duration: AppMotion.micro, curve: AppMotion.enter, child: button),
      ),
    );
  }
}
