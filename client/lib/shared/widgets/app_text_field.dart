import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';

/// Section 13.3 input: label above, filled field, helper/error below, optional unit suffix
/// (kg, °C, %) and a mic button for voice input on numeric fields (speech arrives in M11).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.helper,
    this.unit,
    this.prefixText,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.obscure = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.onVoice,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.fieldKey,
  });

  final String label;
  final TextEditingController? controller;
  final String? helper;
  final String? unit;
  final String? prefixText;

  /// Returns a validation code; translated here.
  final ValidationResult? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onVoice;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.only(bottom: AppSpacing.xs), child: Text(label, style: theme.textTheme.labelLarge)),
      TextFormField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        obscureText: obscure,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        maxLength: maxLength,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validator == null ? null : (v) => validationText(l, validator!(v)),
        decoration: InputDecoration(
          hintText: label,
          helperText: helper,
          prefixText: prefixText,
          counterText: '',
          suffixIcon: onVoice == null ? null : IconButton(icon: const Icon(Icons.mic_rounded), tooltip: l.voiceInput, onPressed: onVoice),
          suffixText: unit,
        ),
      ),
    ]);
  }
}
