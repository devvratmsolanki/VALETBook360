import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/v_breakpoints.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';
import '../widgets/v_primary_button.dart';
import '../widgets/v_states.dart';

/// 7.1 Auth — Login. Single static brand radial behind the wordmark, email +
/// password (show/hide), one thumb-zone primary action. States: idle / loading
/// / error (VBanner, alert/danger). Wordmark fade+rise on mount.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: VMotion.cardEnter,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Motion.reduced(context)) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .login(_email.text, _password.text);
    if (!ok) HapticFeedback.vibrate(); // error pattern (doc §6.8)
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final busy = auth.isBusy;

    return Scaffold(
      backgroundColor: VColors.surface900,
      body: Stack(
        children: [
          // Single static brand radial behind the wordmark (doc §7.1).
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 360,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.6,
                    colors: [Color(0x140073C0), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: VSpace.x6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: context.responsive(compact: 420, expanded: 480),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: VSpace.x12),
                        _wordmark(),
                        const SizedBox(height: VSpace.x12),
                        if (auth.error != null) ...[
                          VBanner(message: auth.error!),
                          const SizedBox(height: VSpace.x4),
                        ],
                        _field(
                          controller: _email,
                          label: 'Email',
                          hint: 'you@company.com',
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          enabled: !busy,
                          validator: (v) =>
                              (v == null || !v.contains('@'))
                                  ? 'Enter a valid email'
                                  : null,
                        ),
                        const SizedBox(height: VSpace.x4),
                        _field(
                          controller: _password,
                          label: 'Password',
                          hint: '••••••••',
                          obscure: _obscure,
                          autofillHints: const [AutofillHints.password],
                          enabled: !busy,
                          onSubmitted: (_) => _submit(),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your password'
                              : null,
                          suffix: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            constraints: const BoxConstraints(
                              minWidth: VTarget.minTouch,
                              minHeight: VTarget.minTouch,
                            ),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: VColors.contentMuted,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        const SizedBox(height: VSpace.x6),
                        VPrimaryButton(
                          label: 'Sign in',
                          loading: busy,
                          onPressed: busy ? null : _submit,
                        ),
                        const SizedBox(height: VSpace.x6),
                        Text(
                          'Powered by LogBook360',
                          textAlign: TextAlign.center,
                          style: VType.caption.copyWith(
                            color: VColors.contentFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wordmark() {
    return FadeTransition(
      opacity: _intro,
      child: AnimatedBuilder(
        animation: _intro,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - _intro.value) * 12),
          child: child,
        ),
        child: Column(
          children: [
            Image.asset(
              'assets/images/logbook360_logo.png',
              height: 54,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(height: VSpace.x3),
            Text(
              'VALET MANAGEMENT',
              textAlign: TextAlign.center,
              style: VType.caption.copyWith(
                color: VColors.contentMuted,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    bool enabled = true,
    TextInputType? keyboardType,
    List<String>? autofillHints,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: VSpace.x1, bottom: VSpace.x2),
          child: Text(label, style: VType.caption),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          style: VType.bodyLg.copyWith(color: VColors.contentStrong),
          decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
        ),
      ],
    );
  }
}
