import 'package:flutter/material.dart';
import '../database/local_record_owner.dart';
import '../services/account_service.dart';
import '../i18n/app_language.dart';

class LocalRecordSession {
  LocalRecordSession.capture()
      : account = AccountService.instance,
        revision = AccountService.instance.sessionRevision;
  final AccountService account;
  final int revision;
  bool get isCurrent =>
      identical(account, AccountService.instance) &&
      revision == account.sessionRevision;
  void requireCurrent() {
    if (!isCurrent) {
      throw AccountException(
          'Konto zmieniło się. Otwórz rejestr ponownie. / Account changed. Reopen the record.');
    }
  }

  Future<LocalRecordOwner> captureOwner() async {
    requireCurrent();
    final owner = await LocalRecordOwner.capture();
    requireCurrent();
    return owner;
  }
}

/// Lists restart for the current account; a record/editor/modal must never
/// restart with its old initial data under a different account.
class LocalRecordScope extends StatefulWidget {
  const LocalRecordScope(
      {super.key,
      required this.builder,
      this.restartOnAccountChange = true,
      this.originSession});
  final Widget Function(BuildContext, LocalRecordSession) builder;
  final bool restartOnAccountChange;
  final LocalRecordSession? originSession;
  @override
  State<LocalRecordScope> createState() => _LocalRecordScopeState();
}

class _LocalRecordScopeState extends State<LocalRecordScope> {
  late LocalRecordSession _session;
  @override
  void initState() {
    super.initState();
    _session = widget.originSession ?? LocalRecordSession.capture();
    _session.account.addListener(_changed);
  }

  void _changed() {
    if (!mounted || _session.isCurrent) return;
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    setState(() {
      if (widget.restartOnAccountChange) {
        final previous = _session.account;
        _session = LocalRecordSession.capture();
        if (!identical(previous, _session.account)) {
          previous.removeListener(_changed);
          _session.account.addListener(_changed);
        }
      }
    });
  }

  @override
  void dispose() {
    _session.account.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_session.isCurrent
      ? Material(
          child: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(context.tr(
                        pl: 'Konto zmieniło się. Otwórz rejestr ponownie.',
                        en: 'The account changed. Reopen the record.')),
                    TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text(context.tr(pl: 'Zamknij', en: 'Close'))),
                  ]))))
      : KeyedSubtree(
          key: ValueKey((_session.account, _session.revision)),
          child: widget.builder(context, _session));
}
