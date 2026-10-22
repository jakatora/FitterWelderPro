import 'package:flutter/material.dart';
import '../../database/local_record_owner.dart';
import '../../services/account_service.dart';
import '../../i18n/app_language.dart';

/// UI/data snapshot, captured before opening a modal or starting async I/O.
class JournalViewSession {
  JournalViewSession._(this.account, this.revision);
  factory JournalViewSession.capture() {
    final account = AccountService.instance;
    return JournalViewSession._(account, account.sessionRevision);
  }
  final AccountService account;
  final int revision;
  bool get isCurrent =>
      identical(account, AccountService.instance) &&
      revision == account.sessionRevision;
  void requireCurrent() {
    if (!isCurrent) {
      throw AccountException(
          'Sesja dziennika zmieniła się. / Journal session changed.');
    }
  }

  Future<LocalRecordOwner> captureOwner() async {
    requireCurrent();
    final owner = await LocalRecordOwner.capture();
    requireCurrent();
    return owner;
  }
}

/// Recreate the journal list on an identity transition, removing old rows,
/// filters, project headers and pending async results from the visible tree.
class JournalAccountView extends StatefulWidget {
  const JournalAccountView({super.key, required this.builder});
  final Widget Function(BuildContext, JournalViewSession) builder;
  @override
  State<JournalAccountView> createState() => _JournalAccountViewState();
}

class _JournalAccountViewState extends State<JournalAccountView> {
  late JournalViewSession _session;
  @override
  void initState() {
    super.initState();
    _session = JournalViewSession.capture();
    _session.account.addListener(_changed);
  }

  void _changed() {
    if (!mounted || _session.isCurrent) return;
    final previous = _session.account;
    final next = JournalViewSession.capture();
    if (!identical(previous, next.account)) {
      previous.removeListener(_changed);
      next.account.addListener(_changed);
    }
    ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    setState(() => _session = next);
  }

  @override
  void dispose() {
    _session.account.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
      key: ValueKey((_session.account, _session.revision)),
      child: widget.builder(context, _session));
}

/// Normal account changes wait until journal modals are closed. Forced
/// revocation hides old-owner content immediately and never submits it.
class JournalSessionView extends StatefulWidget {
  const JournalSessionView(
      {super.key, required this.session, required this.child});
  final JournalViewSession session;
  final Widget child;
  @override
  State<JournalSessionView> createState() => _JournalSessionViewState();
}

class _JournalSessionViewState extends State<JournalSessionView> {
  @override
  void initState() {
    super.initState();
    widget.session.account.addListener(_changed);
    widget.session.account.addSessionPreparer(_prepare);
  }

  @override
  void didUpdateWidget(covariant JournalSessionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session.account, widget.session.account)) {
      oldWidget.session.account.removeListener(_changed);
      oldWidget.session.account.removeSessionPreparer(_prepare);
      widget.session.account.addListener(_changed);
      widget.session.account.addSessionPreparer(_prepare);
    }
  }

  Future<VoidCallback> _prepare() async {
    if (mounted && widget.session.isCurrent) {
      throw AccountException(context.tr(
          pl: 'Zamknij okno dziennika przed zmianą konta.',
          en: 'Close the journal dialog before switching accounts.'));
    }
    return () {};
  }

  void _changed() {
    if (mounted && !widget.session.isCurrent) setState(() {});
  }

  @override
  void dispose() {
    widget.session.account.removeListener(_changed);
    widget.session.account.removeSessionPreparer(_prepare);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.session.isCurrent
      ? widget.child
      : Material(
          child: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(context.tr(
                        pl: 'Konto zmieniło się. Otwórz dziennik ponownie.',
                        en: 'The account changed. Open the journal again.')),
                    const SizedBox(height: 16),
                    TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text(context.tr(pl: 'Zamknij', en: 'Close'))),
                  ]))),
        );
}

Future<T?> showJournalModalBottomSheet<T>(
    {required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useSafeArea = false,
    Color? backgroundColor,
    ShapeBorder? shape}) {
  final session = JournalViewSession.capture();
  return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      shape: shape,
      builder: (context) =>
          JournalSessionView(session: session, child: builder(context)));
}

Future<T?> showJournalDialog<T>(
    {required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true}) {
  final session = JournalViewSession.capture();
  return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) =>
          JournalSessionView(session: session, child: builder(context)));
}
