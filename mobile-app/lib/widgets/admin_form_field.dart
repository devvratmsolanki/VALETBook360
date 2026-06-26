import 'package:flutter/material.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';

/// Labelled form field used across the admin create/edit sheets. Mirrors the
/// `_field` helper in `operator_create_screen.dart` so every admin form shares
/// the same label-above-input look and validation styling.
class AdminFormField extends StatelessWidget {
  const AdminFormField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: VSpace.x1, bottom: VSpace.x2),
            child: Text(label, style: VType.caption),
          ),
          TextFormField(
            controller: controller,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            validator: validator,
            style: VType.bodyLg.copyWith(color: VColors.contentStrong),
            decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
          ),
        ],
      ),
    );
  }
}

/// The dark grab-handle + rounded-top container chrome shared by every admin
/// modal bottom sheet (matches `operator_create_screen`'s sheet shell).
class AdminSheetShell extends StatelessWidget {
  const AdminSheetShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: VColors.surface900,
          borderRadius: BorderRadius.vertical(top: Radius.circular(VRadius.xl)),
          border: Border(top: BorderSide(color: VColors.surface700, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              VSpace.x5,
              VSpace.x4,
              VSpace.x5,
              VSpace.x6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: VSpace.x5),
                    decoration: BoxDecoration(
                      color: VColors.surface600,
                      borderRadius: BorderRadius.circular(VRadius.full),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Password-policy validator shared by the company-owner and staff create
/// forms: 8+ chars with at least one letter and one digit (matches the backend
/// policy in the contract and `isValidPassword` in the legacy web app).
String? validatePassword(String? v) {
  final s = (v ?? '');
  if (s.isEmpty) return 'Password is required';
  if (s.length < 8) return 'At least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'[0-9]').hasMatch(s)) {
    return 'Needs at least one letter and one number';
  }
  return null;
}

/// Email validator shared across the admin create forms.
String? validateEmail(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Email is required';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
    return 'Enter a valid email';
  }
  return null;
}
