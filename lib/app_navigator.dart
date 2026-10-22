import 'package:flutter/material.dart';

const kAssistantRouteOrigin = 'assistant';

/// A presentation of the existing global conversation, without a second engine.
class AssistantPanelPage extends StatelessWidget {
  const AssistantPanelPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}

const kAssistantPanelPresentation = 'global-assistant-presentation';

final appNavigatorKey = GlobalKey<NavigatorState>();
final appRoutes = AppRouteObserver();

/// Tracks the actual top route, including dialogs, without polling the UI.
class AppRouteObserver extends NavigatorObserver with ChangeNotifier {
  final _routes = <Route<dynamic>>[];
  Route<dynamic>? get top => _routes.lastOrNull;
  bool get assistantPresentation =>
      top?.settings.name == 'tool:assistant' &&
      top?.settings.arguments == kAssistantPanelPresentation;
  bool get assistantAvailable =>
      top != null &&
      top is! PopupRoute &&
      (top!.isFirst || (top!.settings.name?.startsWith('tool:') ?? false)) &&
      (assistantPresentation ||
          !const {'tool:assistant', 'tool:iso_scanner'}
              .contains(top!.settings.name));
  String? get toolId {
    final name = top?.settings.name;
    return name != null && name.startsWith('tool:') ? name.substring(5) : null;
  }

  void _changed() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null && route.isFirst) _routes.clear();
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _changed();
  }
}
