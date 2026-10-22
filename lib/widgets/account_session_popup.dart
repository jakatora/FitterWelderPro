import 'package:flutter/material.dart';
import '../services/account_service.dart';

/// A popup may outlive its originating page. Bind it to the opening session,
/// hiding its contents and removing only its own route when that session ends.
WidgetBuilder _boundBuilder(WidgetBuilder builder) {
  final account = AccountService.instance;
  final revision = account.sessionRevision;
  return (_) =>
      _SessionPopup(account: account, revision: revision, builder: builder);
}

Future<T?> showOwnerBoundDialog<T>(
        {required BuildContext context,
        required WidgetBuilder builder,
        bool barrierDismissible = true}) =>
    showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: _boundBuilder(builder));
Future<T?> showOwnerBoundBottomSheet<T>(
        {required BuildContext context,
        required WidgetBuilder builder,
        bool isScrollControlled = false,
        bool? showDragHandle,
        Color? backgroundColor,
        ShapeBorder? shape}) =>
    showModalBottomSheet<T>(
        context: context,
        builder: _boundBuilder(builder),
        isScrollControlled: isScrollControlled,
        showDragHandle: showDragHandle,
        backgroundColor: backgroundColor,
        shape: shape);

class _SessionPopup extends StatefulWidget {
  const _SessionPopup(
      {required this.account, required this.revision, required this.builder});
  final AccountService account;
  final int revision;
  final WidgetBuilder builder;
  @override
  State<_SessionPopup> createState() => _SessionPopupState();
}

class _SessionPopupState extends State<_SessionPopup> {
  bool _hidden = false;
  void _changed() {
    if (_hidden ||
        !mounted ||
        widget.account.sessionRevision == widget.revision &&
            identical(widget.account, AccountService.instance)) {
      return;
    }
    setState(() => _hidden = true);
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route?.navigator;
      if (route != null && route.isActive && navigator != null) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    widget.account.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _hidden ||
          widget.account.sessionRevision != widget.revision ||
          !identical(widget.account, AccountService.instance)
      ? const SizedBox.shrink()
      : widget.builder(context);
}
