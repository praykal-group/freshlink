import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_backend.dart';
import '../../core/auth/session.dart';
import '../../core/config/app_flavor.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';

/// Shared scaffold of the auth screens: centred column, max 480 px wide, scrolls at text scale 2.0.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, this.subtitle, required this.children, this.showBack = false});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final config = ProviderScope.containerOf(context).read(flavorConfigProvider);
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.screenPadding(context)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: context.tokens.flavorAccent, shape: BoxShape.circle)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(config.appName, style: t.labelLarge?.copyWith(color: p.textSecondary))),
                ]),
                const SizedBox(height: AppSpacing.xl),
                Text(title, style: t.headlineMedium),
                if (subtitle != null) ...[const SizedBox(height: AppSpacing.sm), Text(subtitle!, style: t.bodyMedium?.copyWith(color: p.textSecondary))],
                const SizedBox(height: AppSpacing.xl),
                ...children,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Language picker on the login screen (Section 10.2).
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  static const names = {'en': 'English', 'hi': 'हिन्दी', 'mr': 'मराठी'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider).languageCode;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.l10n.language, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
        for (final e in names.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: current == e.key,
            onSelected: (_) => ref.read(localeProvider.notifier).set(e.key),
          ),
      ]),
    ]);
  }
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// The message shown once after being signed out (wrong app, other device, ...).
class SignOutReasonBanner extends ConsumerWidget {
  const SignOutReasonBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final text = s is SignedOut ? signOutReasonText(context.l10n, s.reason) : null;
    if (text == null) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('signout-reason'),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: p.critical.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.input), border: Border.all(color: p.critical.withValues(alpha: 0.5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_rounded, color: p.critical),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ]),
        ),
      ),
    );
  }
}

/// Driver / operator login (AUTH-02): +91 mobile number → SMS OTP.
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key, this.showBack = false});
  final bool showBack;

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final phone = Validators.toE164India(_phone.text);
    try {
      await ref.read(authBackendProvider).sendPhoneOtp(phone);
      if (mounted) context.push('/otp', extra: phone);
    } on AuthFailure catch (e) {
      if (mounted) _snack(context, authFailureText(context.l10n, e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuthScaffold(
      title: l.loginTitle,
      subtitle: l.loginSubtitlePhone,
      showBack: widget.showBack,
      children: [
        const SignOutReasonBanner(),
        Form(
          key: _form,
          child: AppTextField(
            fieldKey: const Key('phone'),
            label: l.phoneLabel,
            helper: l.phoneHelper,
            controller: _phone,
            prefixText: '+91 ',
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            autofillHints: const [AutofillHints.telephoneNumberNational],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _send(),
            validator: Validators.indianMobile,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(key: const Key('send-code'), label: l.sendCode, onPressed: _send, busy: _busy),
        const SizedBox(height: AppSpacing.xl),
        const LanguagePicker(),
      ],
    );
  }
}

/// 6-digit OTP (six boxes over one field, so paste and Android SMS autofill work), resend after 30 s.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});
  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _wait = 30;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _code.addListener(() {
      setState(() => _error = null);
      if (_code.text.length == 6) _verify();
    });
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final l = context.l10n;
    if (Validators.otp(_code.text) != null) {
      setState(() => _error = l.errorOtp);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authBackendProvider).verifyPhoneOtp(widget.phone, _code.text);
      await ref.read(sessionProvider.notifier).completeSignIn();
      // Refused after the OTP (wrong app for the role, not registered, ...): the login screen shows why.
      if (mounted && ref.read(sessionProvider) is SignedOut) context.go('/login');
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = authFailureText(l, e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final l = context.l10n;
    try {
      await ref.read(authBackendProvider).sendPhoneOtp(widget.phone);
      if (mounted) _snack(context, l.codeResent);
      _startTimer();
    } on AuthFailure catch (e) {
      if (mounted) _snack(context, authFailureText(l, e.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final digits = _code.text.split('');
    return AuthScaffold(
      title: l.otpTitle,
      subtitle: l.otpSentTo(widget.phone),
      showBack: true,
      children: [
        Semantics(
          label: l.otpLabel,
          textField: true,
          child: Stack(children: [
            // The real (invisible) field: SMS autofill + paste.
            Opacity(
              opacity: 0,
              child: TextField(
                key: const Key('otp'),
                controller: _code,
                focusNode: _focus,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              ),
            ),
            GestureDetector(
              onTap: () => _focus.requestFocus(),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: List.generate(6, (i) {
                  final filled = i < digits.length;
                  final active = i == digits.length;
                  return AnimatedContainer(
                    duration: AppMotion.micro,
                    constraints: BoxConstraints(minWidth: 44, minHeight: context.tokens.minTarget),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: p.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border: Border.all(color: _error != null ? p.critical : (active ? p.primary : p.outline), width: active ? 2 : 1),
                    ),
                    child: Text(filled ? digits[i] : '', style: AppThemeDigits.style(t)),
                  );
                }),
              ),
            ),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(_error!, key: const Key('otp-error'), style: t.bodySmall?.copyWith(color: p.critical))),
        const SizedBox(height: AppSpacing.xl),
        AppButton(key: const Key('verify'), label: l.verify, onPressed: _verify, busy: _busy),
        const SizedBox(height: AppSpacing.md),
        TextButton(onPressed: _wait == 0 ? _resend : null, child: Text(_wait == 0 ? l.resendCode : l.resendIn(_wait))),
        TextButton(onPressed: () => context.pop(), child: Text(l.changeNumber)),
      ],
    );
  }
}

class AppThemeDigits {
  const AppThemeDigits._();
  static TextStyle? style(TextTheme t) => t.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Manager / web login (AUTH-03): Google, email + password, reset link, or phone OTP.
class ManagerLoginScreen extends ConsumerStatefulWidget {
  const ManagerLoginScreen({super.key});

  @override
  ConsumerState<ManagerLoginScreen> createState() => _ManagerLoginScreenState();
}

class _ManagerLoginScreenState extends ConsumerState<ManagerLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _googleBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {bool google = false}) async {
    setState(() => google ? _googleBusy = true : _busy = true);
    try {
      await action();
      await ref.read(sessionProvider.notifier).completeSignIn();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.code == AuthFailureCode.emailNotConfirmed) {
        context.go('/verify-email', extra: _email.text.trim());
      } else if (e.code != AuthFailureCode.cancelled) {
        _snack(context, authFailureText(context.l10n, e.code));
      }
    } finally {
      if (mounted) setState(() => google ? _googleBusy = false : _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    await _run(() => ref.read(authBackendProvider).signInWithEmail(_email.text.trim(), _password.text));
  }

  Future<void> _forgot() async {
    final l = context.l10n;
    if (Validators.email(_email.text) != null) {
      _snack(context, l.errorEmail);
      return;
    }
    try {
      await ref.read(authBackendProvider).sendPasswordReset(_email.text.trim());
    } on AuthFailure catch (e) {
      if (e.code == AuthFailureCode.rateLimited || e.code == AuthFailureCode.network || e.code == AuthFailureCode.notConfigured) {
        if (mounted) _snack(context, authFailureText(l, e.code));
        return;
      }
    }
    // Same answer whether or not the address exists (no account enumeration).
    if (mounted) _snack(context, l.resetSent);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return AuthScaffold(
      title: l.loginTitle,
      children: [
        const SignOutReasonBanner(),
        AppButton(
          key: const Key('google'),
          label: l.continueWithGoogle,
          icon: Icons.account_circle_rounded,
          kind: AppButtonKind.tonal,
          busy: _googleBusy,
          onPressed: () => _run(() => ref.read(authBackendProvider).signInWithGoogle(), google: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Row(children: [
            const Expanded(child: Divider()),
            Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md), child: Text(l.orDivider, style: TextStyle(color: p.textSecondary))),
            const Expanded(child: Divider()),
          ]),
        ),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(children: [
              AppTextField(
                fieldKey: const Key('email'),
                label: l.emailLabel,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                validator: Validators.email,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                fieldKey: const Key('password'),
                label: l.passwordLabel,
                controller: _password,
                obscure: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _signIn(),
                validator: Validators.password,
              ),
            ]),
          ),
        ),
        Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: _forgot, child: Text(l.forgotPassword))),
        const SizedBox(height: AppSpacing.md),
        AppButton(key: const Key('sign-in'), label: l.signIn, onPressed: _signIn, busy: _busy),
        const SizedBox(height: AppSpacing.md),
        TextButton(onPressed: () => context.push('/login/phone'), child: Text(l.usePhoneInstead)),
        const SizedBox(height: AppSpacing.lg),
        const LanguagePicker(),
      ],
    );
  }
}

/// "Check your inbox" for an unconfirmed manager email (AUTH-03).
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.email});
  final String? email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _busy = false;

  String get _email {
    final s = ref.read(sessionProvider);
    return widget.email ?? (s is NeedsEmailVerification ? s.email : '');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuthScaffold(
      title: l.verifyEmailTitle,
      subtitle: l.verifyEmailBody(_email),
      children: [
        Icon(Icons.mark_email_unread_rounded, size: 64, color: context.palette.primary),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: l.resendEmail,
          kind: AppButtonKind.tonal,
          busy: _busy,
          onPressed: () async {
            setState(() => _busy = true);
            try {
              await ref.read(authBackendProvider).resendEmailConfirmation(_email);
              if (context.mounted) _snack(context, l.emailResent);
            } on AuthFailure catch (e) {
              if (context.mounted) _snack(context, authFailureText(l, e.code));
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(label: l.backToLogin, kind: AppButtonKind.outlined, onPressed: () => ref.read(sessionProvider.notifier).signOut()),
      ],
    );
  }
}

/// Login entry per flavor (Section 10.3).
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(flavorProvider).loginMethod == LoginMethod.phoneOtp ? const PhoneLoginScreen() : const ManagerLoginScreen();
}
