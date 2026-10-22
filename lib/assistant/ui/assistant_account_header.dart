import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_navigator.dart';
import '../../i18n/app_language.dart';
import '../../screens/account_screen.dart';
import '../../services/account_service.dart';

/// Own account only. Public-profile consent does not hide identity from its
/// owner; email, qualifications, credentials and tokens are never rendered here.
class AssistantAccountHeader extends StatefulWidget {
  const AssistantAccountHeader({super.key});

  @override
  State<AssistantAccountHeader> createState() => _AssistantAccountHeaderState();
}

class _AssistantAccountHeaderState extends State<AssistantAccountHeader> {
  final _account = AccountService.instance;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      // Empty OS storage does not create a device identity or make HTTP calls.
      await _account.load();
    } catch (_) {
      // Storage can be unavailable. The existing account form handles retry;
      // never turn an account restore failure into a blocked calculator.
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _account,
        builder: (context, _) {
          String ownField(String key) =>
              (_account.account?[key] as String?)?.trim() ?? '';
          final name = ownField('displayName');
          final profession = ownField('profession');
          final identity = _account.account == null
              ? context.tr(
                  pl: _restoring
                      ? 'Sprawdzam konto…'
                      : _account.needsIdentityRefresh
                          ? 'Otwórz profil, aby ponowić'
                          : 'Zaloguj się',
                  en: _restoring
                      ? 'Checking account…'
                      : _account.needsIdentityRefresh
                          ? 'Open profile to retry'
                          : 'Sign in')
              : [
                  name.isEmpty
                      ? context.tr(pl: 'Moje konto', en: 'My account')
                      : name,
                  if (profession.isNotEmpty) profession,
                ].join(' · ');
          final label = context.tr(
              pl: 'Konto i profil zawodowy',
              en: 'Account and professional profile');
          return Tooltip(
            message: label,
            child: InkWell(
              key: const Key('assistant-account'),
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                final navigator = appNavigatorKey.currentState;
                if (navigator == null) return;
                // An unnamed credential route hides the global assistant.
                unawaited(navigator.push(MaterialPageRoute<void>(
                    builder: (_) => const AccountScreen())));
              },
              child: Semantics(
                button: true,
                label: label,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr(pl: 'Asystent', en: 'Assistant'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge),
                      Text(identity,
                          key: const Key('assistant-account-identity'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
