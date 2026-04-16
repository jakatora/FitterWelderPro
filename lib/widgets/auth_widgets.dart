import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

/// Waliduje adres email używając wyrażenia regularnego
bool isValidEmail(String email) {
  return RegExp(
    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
    caseSensitive: false,
  ).hasMatch(email.trim());
}

/// Widget pola tekstowego dla adresu email z wbudowaną walidacją
class EmailTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? Function(String?)? validator;

  const EmailTextField({
    super.key,
    required this.controller,
    this.labelText,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLabelText = labelText ?? context.tr(pl: 'E-mail', en: 'Email');
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: effectiveLabelText,
        border: const OutlineInputBorder(),
      ),
      validator: validator ?? (value) {
        final s = (value ?? '').trim();
        if (s.isEmpty) return context.tr(pl: 'Wpisz e-mail.', en: 'Enter an email.');
        if (!isValidEmail(s)) return context.tr(pl: 'Nieprawidłowy e-mail.', en: 'Invalid email.');
        return null;
      },
    );
  }
}

/// Widget pola tekstowego dla hasła z wbudowaną walidacją
class PasswordTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? Function(String?)? validator;
  final int? minLength;
  final bool obscureText;

  const PasswordTextField({
    super.key,
    required this.controller,
    this.labelText,
    this.validator,
    this.minLength,
    this.obscureText = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLabelText = labelText ?? context.tr(pl: 'Hasło', en: 'Password');
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: effectiveLabelText,
        border: const OutlineInputBorder(),
      ),
      validator: validator ?? (value) {
        if (value == null || value.isEmpty) return context.tr(pl: 'Wpisz hasło.', en: 'Enter a password.');
        if (minLength != null && value.length < minLength!) {
          return context.tr(pl: 'Minimum $minLength znaków.', en: 'Minimum $minLength characters.');
        }
        return null;
      },
    );
  }
}

/// Widget przycisku z wskaźnikiem ładowania
class LoadingButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final Widget child;
  final double? width;
  final double height;

  const LoadingButton({
    super.key,
    required this.onPressed,
    required this.loading,
    required this.child,
    this.width,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : child,
      ),
    );
  }
}

/// Widget do wyświetlania komunikatu błędu
class ErrorMessage extends StatelessWidget {
  final String? message;

  const ErrorMessage({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return Text(
      message!,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

/// Widget ikony przycisku polityki prywatności
class PrivacyPolicyButton extends StatelessWidget {
  final VoidCallback onPressed;

  const PrivacyPolicyButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.tr(pl: 'Polityka prywatności', en: 'Privacy policy'),
      icon: const Icon(Icons.privacy_tip_outlined),
      onPressed: onPressed,
    );
  }
}
